# What the dashboard's daily refresh needs: a role that only jobs in the repo's `dashboard`
# GitHub environment can assume, allowed to query the gold tables in this workgroup and
# nothing else, and its ARN for the workflow to read.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  account = data.aws_caller_identity.current.account_id
  region  = data.aws_region.current.region
  glue    = "arn:aws:glue:${local.region}:${local.account}"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${var.oidc_subject_prefix}:environment:${var.github_environment}"]
    }
  }
}

data "aws_iam_policy_document" "read_gold" {
  statement {
    sid = "QueryInWorkgroup"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetWorkGroup",
    ]
    resources = ["arn:aws:athena:${local.region}:${local.account}:workgroup/${var.workgroup_name}"]
  }

  statement {
    sid       = "ReadGoldTables"
    actions   = ["glue:GetDatabase", "glue:GetTable", "glue:GetTables", "glue:GetPartitions"]
    resources = ["${local.glue}:catalog", "${local.glue}:database/${var.gold_database_name}", "${local.glue}:table/${var.gold_database_name}/*"]
  }

  # The gold tables' files, and the query results Athena writes (and the refresh downloads).
  statement {
    sid       = "ReadGoldFiles"
    actions   = ["s3:GetObject"]
    resources = ["${var.warehouse_bucket_arn}/tables/${var.gold_database_name}/*"]
  }
  statement {
    sid       = "QueryResults"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${var.warehouse_bucket_arn}/athena-results/*"]
  }
  statement {
    sid       = "ListWarehouse"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.warehouse_bucket_arn]
  }
}

resource "aws_iam_role" "dashboard" {
  name                 = "${var.name}-dashboard"
  description          = "GitHub Actions: query the gold tables for the dashboard (environment ${var.github_environment})"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "read_gold" {
  name   = "read-gold"
  role   = aws_iam_role.dashboard.id
  policy = data.aws_iam_policy_document.read_gold.json
}

resource "aws_ssm_parameter" "role_arn" {
  #checkov:skip=CKV2_AWS_34:Not a secret: a role ARN, which workflow logs show anyway
  name        = "/github/${var.github_repository}/${var.github_environment}/DASHBOARD_ROLE_ARN"
  description = "GitHub environment variable DASHBOARD_ROLE_ARN for ${var.github_repository} (${var.github_environment})"
  type        = "String"
  value       = aws_iam_role.dashboard.arn
}
