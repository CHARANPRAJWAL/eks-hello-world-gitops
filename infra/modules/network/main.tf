# -----------------------------------------------------------------------------
# Network module: a VPC across 3 AZs with public and private subnets and a
# single NAT gateway.
#
# Wraps the community terraform-aws-modules/vpc module rather than hand-rolling
# subnets/route tables/NAT. That module is battle-tested and its EKS-specific
# subnet tagging is easy to get subtly wrong by hand — a wrong tag and the AWS
# Load Balancer Controller silently fails to place LBs.
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  # Single NAT gateway: nodes are in private subnets and need egress for image
  # pulls and AWS API calls, but one NAT (not one-per-AZ) keeps the demo cheap.
  # Trade-off documented in TRADEOFFS.md: a single-AZ NAT outage kills egress
  # for the whole cluster. Production would set one_nat_gateway_per_az = true.
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags the EKS control plane and the AWS Load Balancer Controller rely on to
  # discover which subnets to use for internal vs internet-facing load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = var.tags
}
