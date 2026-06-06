###############################################################################
# IAM: GitHub Actions OIDC deploy role + Lambda execution role
#
# Two least-privilege roles:
#   1. github_actions_deploy  - assumed from GitHub Actions via OIDC, scoped to
#      repo:fischerlynn/aws-govcloud-reference. Permissions limited to the services this stack
#      manages (lambda, apigw, dynamodb, s3, logs) plus a tightly-scoped
#      iam:PassRole for the Lambda execution role only.
#   2. lambda_exec            - the function's runtime role: write its own logs,
#      read/write the app DynamoDB table, read/write the app S3 bucket, and
#      emit X-Ray traces. Nothing more.
###############################################################################

#######################################
# 1. GitHub Actions OIDC provider
#######################################
# Thumbprint list is no longer validated by AWS for this well-known IdP, but a
# value is still required by the API. GitHub's current root CA thumbprint:
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "${local.name_prefix}-github-oidc"
  }
}

# Trust policy: only the GitHub OIDC provider, only for the configured repo,
# and only when the audience is sts.amazonaws.com.
data "aws_iam_policy_document" "github_trust" {
  statement {
    sid     = "GitHubOidcAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_oidc_sub]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name                 = "${local.name_prefix}-gha-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600

  tags = {
    Name = "${local.name_prefix}-gha-deploy"
  }
}

# Least-privilege deploy permissions: scoped to this stack's services. ARNs are
# constrained to the project name prefix where the API supports it.
data "aws_iam_policy_document" "github_deploy" {
  # Lambda management for this project's functions.
  statement {
    sid    = "LambdaManage"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:ListVersionsByFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:ListTags",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
      # The provider reads these per-function config endpoints on every refresh.
      # Like the S3 case, they are not implied by GetFunction, so each missing
      # one fails the plan with AccessDenied (e.g. GetFunctionCodeSigningConfig).
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:GetFunctionConcurrency",
      "lambda:GetFunctionEventInvokeConfig",
      "lambda:GetRuntimeManagementConfig",
      "lambda:GetFunctionUrlConfig",
    ]
    resources = [
      "arn:${local.partition}:lambda:${local.region}:${local.account_id}:function:${var.project}-*",
    ]
  }

  # HTTP API (apigatewayv2) management. The apigateway API is not ARN-scopable
  # per-resource for most actions, so it is constrained by region/account.
  statement {
    sid    = "ApiGatewayManage"
    effect = "Allow"
    actions = [
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:PATCH",
      "apigateway:DELETE",
    ]
    resources = [
      "arn:${local.partition}:apigateway:${local.region}::/apis",
      "arn:${local.partition}:apigateway:${local.region}::/apis/*",
      "arn:${local.partition}:apigateway:${local.region}::/tags/*",
    ]
  }

  # DynamoDB table management for this project's tables.
  statement {
    sid    = "DynamoDbManage"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:UpdateTable",
      "dynamodb:UpdateContinuousBackups",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:ListTagsOfResource",
    ]
    resources = [
      "arn:${local.partition}:dynamodb:${local.region}:${local.account_id}:table/${var.project}-*",
    ]
  }

  # Terraform remote-state locking: the S3 backend reads/writes a single lock
  # item in the DynamoDB lock table. Data-plane actions, scoped to the lock
  # table only (NOT the app table).
  statement {
    sid    = "TerraformStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [
      "arn:${local.partition}:dynamodb:${local.region}:${local.account_id}:table/${var.project}-tflock",
    ]
  }

  # S3: manage the project's buckets (app bucket + state bucket prefix).
  statement {
    sid    = "S3Manage"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucket*",
      "s3:PutBucket*",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      # The AWS provider reads every bucket sub-config on refresh. These config
      # actions have NO "Bucket" in their IAM action name, so s3:GetBucket*
      # above does not cover them — they must be listed explicitly or the plan
      # fails with AccessDenied (e.g. s3:GetAccelerateConfiguration).
      "s3:GetAccelerateConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetAnalyticsConfiguration",
      "s3:GetMetricsConfiguration",
      "s3:GetInventoryConfiguration",
      "s3:GetIntelligentTieringConfiguration",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:${local.partition}:s3:::${var.project}-*",
      "arn:${local.partition}:s3:::${var.project}-*/*",
    ]
  }

  # CloudWatch Logs for the function and API access logs. Mutating actions are
  # scoped to this project's log groups.
  statement {
    sid    = "LogsManage"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource",
    ]
    resources = [
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${var.project}-*",
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/apigateway/${var.project}-*",
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${var.project}-*:*",
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/apigateway/${var.project}-*:*",
    ]
  }

  # logs:DescribeLogGroups is an account-level list action: IAM evaluates it
  # against the wildcard log-group resource, NOT individual group ARNs, so it
  # cannot be scoped to this project's groups. Read-only, region/account bound.
  statement {
    sid       = "LogsDescribe"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*"]
  }

  # Read IAM roles/policies the stack manages, and create/update them.
  statement {
    sid    = "IamManageStackRoles"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-*",
    ]
  }

  # Manage the GitHub Actions OIDC provider this stack owns. Scoped to the one
  # well-known GitHub IdP provider ARN (read on refresh; full lifecycle so
  # destroy/recreate stays idempotent).
  statement {
    sid    = "ManageGithubOidcProvider"
    effect = "Allow"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviderTags",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com",
    ]
  }

  # PassRole limited to the Lambda execution role only, and only to Lambda.
  statement {
    sid       = "PassLambdaExecRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.lambda_exec.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${local.name_prefix}-gha-deploy"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}

#######################################
# 2. Lambda execution role
#######################################
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.name_prefix}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = {
    Name = "${local.name_prefix}-lambda-exec"
  }
}

data "aws_iam_policy_document" "lambda_exec" {
  # Write only to this function's own log stream.
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.lambda.arn}:*",
    ]
  }

  # X-Ray trace segments (tracing_config = Active).
  statement {
    sid    = "Xray"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }

  # Read/write the single app DynamoDB table (and its indexes).
  statement {
    sid    = "DynamoDataAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
    ]
    resources = [
      aws_dynamodb_table.app.arn,
      "${aws_dynamodb_table.app.arn}/index/*",
    ]
  }

  # Read/write objects in the single app S3 bucket.
  statement {
    sid    = "S3DataAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.app.arn}/*",
    ]
  }

  statement {
    sid       = "S3ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.app.arn]
  }
}

resource "aws_iam_role_policy" "lambda_exec" {
  name   = "${local.name_prefix}-lambda-exec"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_exec.json
}
