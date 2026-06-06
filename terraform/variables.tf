###############################################################################
# Input variables
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short project identifier used in resource names and tags."
  type        = string
  default     = "aws-govcloud-reference"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod). Used in names and tags."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owning team or individual for cost-allocation tags."
  type        = string
  default     = "FischerLynn LLC"
}

variable "github_repo" {
  description = <<-EOT
    GitHub repository in "org/repo" form that is allowed to assume the
    GitHub Actions deploy role via OIDC. Provide via tfvars; no default so
    the trust policy is never accidentally left wide open.
  EOT
  type        = string
}

variable "lambda_log_retention_days" {
  description = "CloudWatch Logs retention for the Lambda function."
  type        = number
  default     = 14
}
