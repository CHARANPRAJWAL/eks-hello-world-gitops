variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "hello-world-dev"
}

variable "cluster_version" {
  description = "Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint. Set to YOUR_IP/32 for a real run."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Node group instance types."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "SPOT"
}

variable "bootstrap_argocd" {
  description = "Install Argo CD and the root app-of-apps. Enable in a second apply once the cluster API is reachable."
  type        = bool
  default     = false
}

variable "gitops_repo_url" {
  description = "Git repository URL Argo CD watches (set once pushed to GitHub)."
  type        = string
  default     = "https://github.com/CHARANPRAJWAL/eks-hello-world-gitops.git"
}

variable "gitops_target_revision" {
  description = "Git revision Argo CD tracks."
  type        = string
  default     = "main"
}

variable "enable_github_oidc" {
  description = "Create the GitHub OIDC role for CI to push to ECR. Enable once the repo exists."
  type        = bool
  default     = false
}

variable "github_sub_claim" {
  description = "OIDC sub claim to trust, e.g. repo:CHARANPRAJWAL/eks-hello-world-gitops:ref:refs/heads/main"
  type        = string
  default     = "repo:CHARANPRAJWAL/eks-hello-world-gitops:ref:refs/heads/main"
}
