output "bucket_name" {
  value = aws_s3_bucket.warehouse.id
}

output "bucket_arn" {
  value = aws_s3_bucket.warehouse.arn
}

output "workgroup_name" {
  value = aws_athena_workgroup.this.name
}

output "database_names" {
  value = { for layer, db in aws_glue_catalog_database.layer : layer => db.name }
}
