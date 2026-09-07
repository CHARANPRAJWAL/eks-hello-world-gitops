variable "name_prefix" {
  description = "Prefix for the CI role name."
  type        = string
  default     = "hello-world-dev"
}

variable "github_sub_claim" {
  description = "OIDC sub claim to trust, e.g. repo:CHARANPRAJWAL/eks-hello-world-gitops:ref:refs/heads/main or repo:CHARANPRAJWAL/eks-hello-world-gitops:*"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository CI is allowed to push to."
  type        = string
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if one already exists in the account."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of a pre-existing GitHub OIDC provider (used when create_oidc_provider = false)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to the role."
  type        = map(string)
  default     = {}
}
