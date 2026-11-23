# What GitHub Actions needs to deploy one environment's dbt runner: a role that only that
# GitHub environment's jobs can assume, allowed to update and invoke this one function and
# to read the shared registry (push to it, for the environment that builds the image), and
# the values the deploy workflow reads.
#
# The values are published to SSM at /github/<repo>/<environment>/<NAME>; personal-infra's
# GitHub stack turns each into a GitHub environment variable, read as vars.<NAME>.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
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
    # Only jobs in this GitHub environment (which allows only main) get these credentials.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${var.oidc_subject_prefix}:environment:${var.github_environment}"]
    }
  }
}

data "aws_iam_policy_document" "deploy" {
  # Signing in to ECR is account-wide; pushing is limited to this registry.
  statement {
    sid       = "SignInToEcr"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  # Lambda checks that whoever points a function at an image can read it.
  statement {
    sid       = "ReadImages"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    resources = [var.repository_arn]
  }
  dynamic "statement" {
    for_each = var.push_images ? [1] : []
    content {
      sid       = "PushImages"
      actions   = ["ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"]
      resources = [var.repository_arn]
    }
  }
  statement {
    sid       = "UpdateCode"
    actions   = ["lambda:UpdateFunctionCode", "lambda:GetFunction", "lambda:GetFunctionConfiguration"]
    resources = [var.function_arn]
  }
  # The smoke test runs dbt once after each deploy.
  statement {
    sid       = "SmokeTest"
    actions   = ["lambda:InvokeFunction"]
    resources = [var.function_arn]
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.function_name}-deploy"
  description          = "GitHub Actions deploys of ${var.function_name} (environment ${var.github_environment})"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy-${var.function_name}"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

resource "aws_ssm_parameter" "variables" {
  #checkov:skip=CKV2_AWS_34:Not secrets: a role ARN, a function name and a registry URL; GitHub masks the ones with the account ID in workflow logs
  for_each = {
    DEPLOY_ROLE_ARN = aws_iam_role.deploy.arn
    FUNCTION_NAME   = var.function_name
    REPOSITORY_URL  = var.repository_url
  }

  name        = "/github/${var.github_repository}/${var.github_environment}/${each.key}"
  description = "GitHub environment variable ${each.key} for ${var.github_repository} (${var.github_environment})"
  type        = "String"
  value       = each.value
}
