# The dashboard shows production's gold tables, so only prod has this stack.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/terragrunt/modules/dashboard-access"
}

dependency "warehouse" {
  config_path = "../warehouse"

  mock_outputs = {
    bucket_arn     = "arn:aws:s3:::mock-warehouse"
    workgroup_name = "mock"
    database_names = { gold = "mock_gold" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers"]
}

inputs = {
  name                 = local.env.name
  workgroup_name       = dependency.warehouse.outputs.workgroup_name
  gold_database_name   = dependency.warehouse.outputs.database_names["gold"]
  warehouse_bucket_arn = dependency.warehouse.outputs.bucket_arn

  github_repository   = "data-simulator-analytics"
  oidc_subject_prefix = "repo:amcaughan-personal@271645414/data-simulator-analytics@1466249789"
  github_environment  = "dashboard"
}
