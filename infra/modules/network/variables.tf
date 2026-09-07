variable "name" {
  description = "Name prefix for network resources."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name, used for the Kubernetes subnet discovery tags."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 for this VPC sizing."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all AZs (cheaper) instead of one per AZ (resilient)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all network resources."
  type        = map(string)
  default     = {}
}
