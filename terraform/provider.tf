###############################################################################
# AWS provider configuration
#
# Region is driven by var.aws_region. Default tags are applied to every
# taggable resource so cost allocation / ownership is consistent without
# repeating tag blocks on each resource.
###############################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
      Company     = "FischerLynn LLC"
      ManagedBy   = "Terraform"
      Repo        = var.github_repo
    }
  }
}
