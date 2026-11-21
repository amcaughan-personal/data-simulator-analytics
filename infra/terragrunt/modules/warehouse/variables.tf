variable "name" {
  description = "Name prefix for this environment, e.g. data-simulator-analytics-dev"
  type        = string
}

variable "max_bytes_scanned_per_query" {
  description = "Athena cancels any query that would scan more than this"
  type        = number
  default     = 1073741824 # 1 GiB: the whole raw dataset is a few MB
}
