# Where the dbt models live: a bucket for their tables and for Athena's query results, a
# Glue database per layer (bronze, silver, gold), and an Athena workgroup that every query
# runs in. dbt creates and replaces the tables; Terraform owns everything around them.
#
# The models read the ELT's raw tables, which belong to data-simulator-elt.

data "aws_caller_identity" "current" {}

locals {
  bucket_name     = "${var.name}-warehouse-${data.aws_caller_identity.current.account_id}"
  database_prefix = replace(var.name, "-", "_")
  layers = {
    bronze = "Raw rows with proper types and names, one row per source row."
    silver = "Cleaned, deduplicated and joined: one row per transaction, merchants as a dimension."
    gold   = "Metrics for the dashboard."
  }
}

# --------------------------------------------------------------------------------------
# Bucket: tables/ for the models' data, athena-results/ for query results (kept a week)
# --------------------------------------------------------------------------------------

resource "aws_s3_bucket" "warehouse" {
  #checkov:skip=CKV_AWS_21:Versioning isn't needed: every table can be rebuilt from the raw data
  #checkov:skip=CKV_AWS_18:Access logging would cost more than the data it protects; CloudTrail covers the account
  #checkov:skip=CKV_AWS_144:Cross-region replication isn't worth it for tables that can be rebuilt
  #checkov:skip=CKV_AWS_145:SSE-S3 is enough; a customer-managed KMS key adds cost and key management
  #checkov:skip=CKV2_AWS_62:Nothing reacts to new objects
  bucket = local.bucket_name

  # Everything here can be rebuilt from the raw data, so destroying the stack may delete it.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "warehouse" {
  bucket                  = aws_s3_bucket.warehouse.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "warehouse" {
  bucket = aws_s3_bucket.warehouse.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "warehouse" {
  bucket = aws_s3_bucket.warehouse.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "expire-query-results"
    status = "Enabled"
    filter {
      prefix = "athena-results/"
    }
    expiration {
      days = 7
    }
  }
}

data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.warehouse.arn,
      "${aws_s3_bucket.warehouse.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "warehouse" {
  bucket = aws_s3_bucket.warehouse.id
  policy = data.aws_iam_policy_document.tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.warehouse]
}

# --------------------------------------------------------------------------------------
# Glue databases, one per layer
# --------------------------------------------------------------------------------------

resource "aws_glue_catalog_database" "layer" {
  for_each = local.layers

  name         = "${local.database_prefix}_${each.key}"
  description  = "${each.value} Built by dbt in data-simulator-analytics."
  location_uri = "s3://${aws_s3_bucket.warehouse.id}/tables/${each.key}/"
}

# --------------------------------------------------------------------------------------
# Athena workgroup: where results go, and a cap on what one query may scan
# --------------------------------------------------------------------------------------

resource "aws_athena_workgroup" "this" {
  name          = var.name
  description   = "dbt and ad-hoc queries for ${var.name}"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    # A runaway query stops here instead of scanning (and billing) more.
    bytes_scanned_cutoff_per_query = var.max_bytes_scanned_per_query

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${aws_s3_bucket.warehouse.id}/athena-results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}
