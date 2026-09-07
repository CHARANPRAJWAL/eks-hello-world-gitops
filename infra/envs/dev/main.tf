# -----------------------------------------------------------------------------
# dev environment root module.
#
# Thin by design: it wires the network, eks and ecr modules together and passes
# environment-specific values. Adding a `prod` environment is a sibling
# directory that reuses the same modules with different sizing — the criterion
# "easy to extend, not code that works once".
# -----------------------------------------------------------------------------

locals {
  tags = {
    Project     = "devops-assignment"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

module "network" {
  source = "../../modules/network"

  name               = var.cluster_name
  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  az_count           = 3
  single_nat_gateway = true # cost trade-off for dev; see TRADEOFFS.md

  tags = local.tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  cluster_endpoint_public_access = true
  public_access_cidrs            = var.public_access_cidrs

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_min_size       = 2
  node_max_size       = 4
  node_desired_size   = 2

  tags = local.tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name = "hello-world"
  max_image_count = 20

  tags = local.tags
}

# GitHub OIDC role for CI to push to ECR. Off by default; enable once the repo
# exists so github_sub_claim can be set. No static AWS keys are ever created.
module "github_oidc" {
  source = "../../modules/github-oidc"
  count  = var.enable_github_oidc ? 1 : 0

  name_prefix        = var.cluster_name
  github_sub_claim   = var.github_sub_claim
  ecr_repository_arn = module.ecr.repository_arn

  tags = local.tags
}

# Argo CD bootstrap. Gated behind a flag so the base infra (network/eks/ecr)
# can be applied first, then Argo CD in a second `terraform apply
# -var bootstrap_argocd=true` once the cluster API is reachable. This avoids
# the provider trying to talk to a cluster that does not exist yet.
module "argocd" {
  source = "../../modules/argocd"
  count  = var.bootstrap_argocd ? 1 : 0

  gitops_repo_url        = var.gitops_repo_url
  gitops_target_revision = var.gitops_target_revision

  depends_on = [module.eks]
}
