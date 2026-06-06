###############################################################################
# Terraform & provider version constraints
#
# Pinned to keep plans reproducible. AWS provider 5.x is required for the
# HTTP API (apigatewayv2) and the lambda permission / OIDC features used here.
###############################################################################

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}
