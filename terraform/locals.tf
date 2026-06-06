###############################################################################
# Shared locals
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  name_prefix = "${var.project}-${var.environment}"

  # GitHub OIDC subject scoped to the supplied repo (any branch/ref).
  # Tighten to e.g. "repo:org/repo:ref:refs/heads/main" for stricter scope.
  github_oidc_sub = "repo:${var.github_repo}:*"
}
