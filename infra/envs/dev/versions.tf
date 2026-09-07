terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# The helm and kubernetes providers authenticate to the EKS API using a
# short-lived token minted by `aws eks get-token`, so no kubeconfig file or
# static credential is involved. These providers are only exercised when the
# argocd module is enabled (var.bootstrap_argocd), which happens as a second
# apply once the cluster exists.
data "aws_eks_cluster_auth" "this" {
  count = var.bootstrap_argocd ? 1 : 0
  name  = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = var.bootstrap_argocd ? data.aws_eks_cluster_auth.this[0].token : ""
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = var.bootstrap_argocd ? data.aws_eks_cluster_auth.this[0].token : ""
}
