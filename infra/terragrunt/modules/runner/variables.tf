variable "function_name" {
  type = string
}

variable "initial_image_uri" {
  description = "The image the function is created with; deploys replace it"
  type        = string
}

variable "schema_prefix" {
  description = "Glue database prefix for this environment's layers (dbt's target schema)"
  type        = string
}

variable "layer_database_names" {
  description = "This environment's Glue databases, by layer (from the warehouse stack)"
  type        = map(string)
}

variable "workgroup_name" {
  type = string
}

variable "warehouse_bucket_name" {
  type = string
}

variable "warehouse_bucket_arn" {
  type = string
}

variable "raw_database_name" {
  description = "The ELT's raw Glue database (read only)"
  type        = string
}

variable "raw_bucket_name" {
  description = "The ELT's raw bucket (read only)"
  type        = string
}

variable "alert_topic_name" {
  description = "SNS topic to email when a run fails; null for no alarm"
  type        = string
  default     = null
}

variable "log_retention_days" {
  type    = number
  default = 30
}
