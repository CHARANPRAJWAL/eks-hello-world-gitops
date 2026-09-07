variable "repository_name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "max_image_count" {
  description = "Number of most-recent images to retain before expiry."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Tags applied to the repository."
  type        = map(string)
  default     = {}
}
