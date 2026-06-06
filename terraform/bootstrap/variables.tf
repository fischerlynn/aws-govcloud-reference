variable "aws_region" {
  description = "Region for the remote-state bucket and lock table."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project identifier used to name the state resources."
  type        = string
  default     = "aws-govcloud-reference"
}
