###############################################################################
# Lambda function (health / echo)
#
# - Source in ./src is zipped at plan time with archive_file (no build step).
# - Node.js 20 runtime, ARM64 (cheaper per-ms, free-tier friendly).
# - Dedicated CloudWatch log group with bounded retention (cost control).
###############################################################################

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.build/lambda.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-fn"
  retention_in_days = var.lambda_log_retention_days

  tags = {
    Name = "${local.name_prefix}-fn-logs"
  }
}

resource "aws_lambda_function" "fn" {
  function_name = "${local.name_prefix}-fn"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  architectures = ["arm64"]
  memory_size   = 128
  timeout       = 10

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      SERVICE_NAME   = var.project
      DDB_TABLE_NAME = aws_dynamodb_table.app.name
      APP_BUCKET     = aws_s3_bucket.app.bucket
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda_exec,
  ]

  tags = {
    Name = "${local.name_prefix}-fn"
  }
}

# Allow API Gateway (HTTP API) to invoke the function.
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
