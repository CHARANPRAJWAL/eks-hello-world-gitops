# -----------------------------------------------------------------------------
# EKS module: managed control plane + a single spot node group.
#
# Wraps terraform-aws-modules/eks. That module handles the OIDC provider,
# the aws-auth / access-entry wiring, and the add-on lifecycle correctly —
# all things that are easy to misconfigure by hand and hard to debug when
# they break. We keep the module's surface small and opinionated.
# -----------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # The public endpoint is enabled so we can reach the API from a laptop for
  # this demo; locked to var.public_access_cidrs (default your IP, not the
  # world). Private endpoint is also on so in-cluster traffic never leaves the
  # VPC. Production would disable public access entirely and use a bastion/VPN.
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.public_access_cidrs
  cluster_endpoint_private_access      = true

  # Ship control-plane logs to CloudWatch so an audit trail exists.
  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  # Envelope-encrypt Kubernetes Secrets with a dedicated KMS key. Without this,
  # Secrets are only base64-encoded at rest in etcd.
  create_kms_key            = true
  cluster_encryption_config = { resources = ["secrets"] }

  # IRSA: create the OIDC provider so workloads can assume IAM roles via a
  # service account, instead of every pod inheriting the node instance profile.
  enable_irsa = true

  # Grant the identity running Terraform cluster-admin so the apply can create
  # the initial platform resources. Additional admins are added per-env.
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"
  }

  eks_managed_node_groups = {
    default = {
      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      # Nodes live in private subnets; no public IPs.
      subnet_ids = var.private_subnet_ids

      labels = {
        role = "general"
      }

      # Let the Cluster Autoscaler discover and scale this group.
      tags = {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      }
    }
  }

  tags = var.tags
}
