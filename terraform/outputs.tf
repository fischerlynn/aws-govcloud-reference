###############################################################################
# Outputs
###############################################################################

output "api_endpoint" {
  description = "Base invoke URL of the HTTP API ($default stage)."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_health_url" {
  description = "Convenience URL for the health route."
  value       = "${trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")}/health"
}

output "lambda_function_name" {
  description = "Name of the health/echo Lambda function."
  value       = aws_lambda_function.fn.function_name
}

output "dynamodb_table_name" {
  description = "Name of the on-demand application DynamoDB table."
  value       = aws_dynamodb_table.app.name
}

output "app_bucket_name" {
  description = "Name of the application S3 bucket."
  value       = aws_s3_bucket.app.bucket
}

output "github_actions_deploy_role_arn" {
  description = "ARN of the role GitHub Actions assumes via OIDC for deploys."
  value       = aws_iam_role.github_actions_deploy.arn
}
