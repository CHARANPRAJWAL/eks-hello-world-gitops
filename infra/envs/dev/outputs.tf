output "region" {
  description = "AWS region."
  value       = var.region
}

output "cluster_name" {
  description = "EKS cluster name (for `aws eks update-kubeconfig`)."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "ECR repository URL for the app image (CI pushes here)."
  value       = module.ecr.repository_url
}

output "aws_load_balancer_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller (used in gitops values)."
  value       = module.eks.aws_load_balancer_controller_role_arn
}

output "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for the Cluster Autoscaler (used in gitops values)."
  value       = module.eks.cluster_autoscaler_role_arn
}

output "update_kubeconfig_command" {
  description = "Run this to configure kubectl for the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "ci_role_arn" {
  description = "ARN of the GitHub CI role (set as GitHub variable AWS_CI_ROLE_ARN). Null unless enable_github_oidc = true."
  value       = var.enable_github_oidc ? module.github_oidc[0].ci_role_arn : null
}