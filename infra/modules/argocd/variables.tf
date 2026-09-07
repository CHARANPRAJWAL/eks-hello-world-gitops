variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart."
  type        = string
  default     = "7.7.0"
}

variable "gitops_repo_url" {
  description = "Git repo URL Argo CD watches for the app-of-apps."
  type        = string
}

variable "gitops_target_revision" {
  description = "Git branch/tag/commit Argo CD tracks."
  type        = string
  default     = "main"
}
