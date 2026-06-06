output "state_bucket_name" {
  description = "Name of the S3 bucket holding remote Terraform state. Put in ../backend.tf as `bucket`."
  value       = aws_s3_bucket.state.bucket
}

output "lock_table_name" {
  description = "Name of the DynamoDB lock table. Put in ../backend.tf as `dynamodb_table`."
  value       = aws_dynamodb_table.lock.name
}

output "region" {
  description = "Region the state resources live in. Put in ../backend.tf as `region`."
  value       = var.aws_region
}
