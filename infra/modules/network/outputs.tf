output "vpc_id" {
  description = "The VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes and internal LBs)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs (internet-facing LBs)."
  value       = module.vpc.public_subnets
}

output "azs" {
  description = "Availability zones in use."
  value       = local.azs
}
