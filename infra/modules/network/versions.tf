terraform {
  # Pinned to a known-good minor. Patch updates allowed, minor bumps are a
  # deliberate review so a provider change never surprises an apply.
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
  }
}
