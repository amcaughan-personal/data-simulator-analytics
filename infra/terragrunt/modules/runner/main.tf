# The dbt runner: a container Lambda that runs `dbt source freshness` and `dbt build` once a
# day (see runner/), reading the ELT's raw tables and writing this environment's layers.
#
# Terraform owns the function's configuration; CI owns its image. Terraform sets the image
# only when it creates the function. Deploys push a new image and point the function at it.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_sns_topic" "alerts" {
  count = var.alert_topic_name == null ? 0 : 1
  name  = var.alert_topic_name
}

# The ELT's raw bucket, looked up by name: this stack only reads it (and the raw Glue
# database, which IAM refers to by name).
data "aws_s3_bucket" "raw" {
  bucket = var.raw_bucket_name
}

locals {
  account         = data.aws_caller_identity.current.account_id
  region          = data.aws_region.current.region
  glue            = "arn:aws:glue:${local.region}:${local.account}"
  layer_databases = values(var.layer_database_names)
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
}

# --------------------------------------------------------------------------------------
# Permissions: query in this environment's workgroup, read raw, write this environment's
# layers. Nothing else.
# --------------------------------------------------------------------------------------

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "function" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  statement {
    sid = "QueryInOwnWorkgroup"
    actions = [
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetWorkGroup",
    ]
    resources = ["arn:aws:athena:${local.region}:${local.account}:workgroup/${var.workgroup_name}"]
  }

  # dbt lists the catalog's databases and reads table definitions while it plans a run.
  statement {
    sid = "ReadCatalog"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
    ]
    resources = concat(
      ["${local.glue}:catalog", "${local.glue}:database/*"],
      [for db in concat([var.raw_database_name], local.layer_databases) : "${local.glue}:table/${db}/*"],
    )
  }

  statement {
    sid = "WriteOwnLayers"
    actions = [
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:BatchDeleteTable",
      "glue:GetTableVersions",
      "glue:DeleteTableVersion",
      "glue:BatchDeleteTableVersion",
      "glue:CreatePartition",
      "glue:BatchCreatePartition",
      "glue:UpdatePartition",
      "glue:DeletePartition",
      "glue:BatchDeletePartition",
    ]
    resources = concat(
      ["${local.glue}:catalog"],
      [for db in local.layer_databases : "${local.glue}:database/${db}"],
      [for db in local.layer_databases : "${local.glue}:table/${db}/*"],
    )
  }

  statement {
    sid       = "ReadRawFiles"
    actions   = ["s3:GetObject"]
    resources = ["${data.aws_s3_bucket.raw.arn}/*"]
  }

  statement {
    sid       = "WriteWarehouseFiles"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
    resources = ["${var.warehouse_bucket_arn}/*"]
  }

  statement {
    sid       = "ListBuckets"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [data.aws_s3_bucket.raw.arn, var.warehouse_bucket_arn]
  }
}

resource "aws_iam_role" "function" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "function" {
  name   = "run-dbt"
  role   = aws_iam_role.function.id
  policy = data.aws_iam_policy_document.function.json
}

# --------------------------------------------------------------------------------------
# Function
# --------------------------------------------------------------------------------------

resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_117:No VPC: the function calls only AWS APIs, so a VPC would add NAT or endpoint costs without isolating anything
  #checkov:skip=CKV_AWS_50:X-Ray tracing isn't needed for one daily batch job
  #checkov:skip=CKV_AWS_272:Code signing doesn't apply to container images; ECR tags are immutable instead
  #checkov:skip=CKV_AWS_173:The environment holds no secrets, only names
  #checkov:skip=CKV_AWS_116:A failed run isn't retried or kept: the alarm reports it, and the next day's run rebuilds everything
  function_name = var.function_name
  description   = "Runs dbt for data-simulator-analytics"
  role          = aws_iam_role.function.arn
  package_type  = "Image"
  image_uri     = var.initial_image_uri
  architectures = ["x86_64"]

  memory_size = 2048
  timeout     = 900 # Lambda's maximum; a full build takes about two minutes

  # One run at a time, so two builds never write the same tables.
  reserved_concurrent_executions = 1

  environment {
    variables = {
      DBT_SCHEMA_PREFIX    = var.schema_prefix
      DBT_ATHENA_WORKGROUP = var.workgroup_name
      DBT_WAREHOUSE_BUCKET = var.warehouse_bucket_name
    }
  }

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
    log_group             = aws_cloudwatch_log_group.this.name
  }

  depends_on = [aws_iam_role_policy.function]

  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_lambda_function_event_invoke_config" "this" {
  function_name                = aws_lambda_function.this.function_name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 3600
}

# --------------------------------------------------------------------------------------
# Schedule: daily, after the ELT has landed the night's hours
# --------------------------------------------------------------------------------------

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.this.arn]
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.function_name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "invoke-runner"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}

resource "aws_scheduler_schedule" "daily" {
  #checkov:skip=CKV_AWS_297:The schedule's only data is an empty event; AWS-owned encryption is enough
  name                = var.function_name
  schedule_expression = "cron(30 7 * * ? *)" # 07:30 UTC every day

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.this.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})

    retry_policy {
      maximum_retry_attempts       = 3
      maximum_event_age_in_seconds = 3600
    }
  }
}

# --------------------------------------------------------------------------------------
# Alarm: the daily run failed. Only where it notifies someone (prod).
# --------------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "errors" {
  count = var.alert_topic_name == null ? 0 : 1

  alarm_name          = "${var.function_name}-errors"
  alarm_description   = "The daily dbt run failed (stale sources, a failing test or a model error). Its logs say which."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.this.function_name }
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = data.aws_sns_topic.alerts[*].arn
  ok_actions          = data.aws_sns_topic.alerts[*].arn
}
