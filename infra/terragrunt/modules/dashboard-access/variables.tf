variable "name" {
  type = string
}

variable "workgroup_name" {
  type = string
}

variable "gold_database_name" {
  type = string
}

variable "warehouse_bucket_arn" {
  type = string
}

variable "github_repository" {
  description = "Repository name within the amcaughan-personal org"
  type        = string
}

variable "oidc_subject_prefix" {
  description = "The repository part of GitHub's OIDC subject claim (see the repo's OIDC settings)"
  type        = string
}

variable "github_environment" {
  description = "The GitHub environment whose jobs may assume the role"
  type        = string
}
