###############################################################################
# Remote state backend (S3 + DynamoDB lock)
#
# BOOTSTRAP NOTE
# --------------
# This backend depends on an S3 bucket and a DynamoDB lock table that must
# exist BEFORE `terraform init` can use them. Create them ONCE with the tiny
# module in ./bootstrap using LOCAL state, then come back here:
#
#   1. cd bootstrap && terraform init && terraform apply
#        -> outputs: state_bucket_name, lock_table_name
#   2. Fill the values below (or pass them via -backend-config on init).
#   3. cd .. && terraform init -reconfigure
#        -> migrate the root module to the S3 backend.
#
# Backend blocks cannot use variables/interpolation, so the values are
# intentionally left as placeholders to fill from the bootstrap outputs.
# Prefer `terraform init -backend-config=...` in CI to avoid committing them.
###############################################################################

terraform {
  backend "s3" {
    bucket         = "aws-govcloud-reference-tfstate-981257813928"
    key            = "aws-govcloud-reference/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-govcloud-reference-tflock"
    encrypt        = true
  }
}
