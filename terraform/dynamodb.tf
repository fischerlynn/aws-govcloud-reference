###############################################################################
# DynamoDB application table
#
# - PAY_PER_REQUEST (on-demand): scales to zero cost when idle, free-tier
#   friendly, no capacity to manage.
# - Server-side encryption at rest (AWS-owned key by default; flip to a CMK
#   by setting kms_key_arn if a customer-managed key is required).
# - Point-in-time recovery on for safety.
###############################################################################

resource "aws_dynamodb_table" "app" {
  name         = "${local.name_prefix}-app"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = false

  tags = {
    Name = "${local.name_prefix}-app"
  }
}
