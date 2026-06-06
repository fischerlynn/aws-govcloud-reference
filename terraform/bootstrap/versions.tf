terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      Company   = "FischerLynn LLC"
      ManagedBy = "Terraform"
      Purpose   = "tf-remote-state"
    }
  }
}
