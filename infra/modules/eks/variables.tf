variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes control plane version."
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "VPC to place the cluster in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the control plane ENIs and nodes."
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Expose the API server endpoint publicly (locked to public_access_cidrs)."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Default is open; override to your IP/32."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "SPOT"
}

variable "node_min_size" {
  description = "Minimum nodes in the group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum nodes in the group."
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired nodes in the group."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags applied to cluster resources."
  type        = map(string)
  default     = {}
}
