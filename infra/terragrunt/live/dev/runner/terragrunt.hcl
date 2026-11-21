include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/terragrunt/modules/runner"
}

dependency "warehouse" {
  config_path = "../warehouse"

  mock_outputs = {
    bucket_name    = "mock-warehouse"
    bucket_arn     = "arn:aws:s3:::mock-warehouse"
    workgroup_name = "mock"
    database_names = { bronze = "mock_bronze", silver = "mock_silver", gold = "mock_gold" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers"]
}

dependency "registry" {
  config_path = "../../shared/registry"

  mock_outputs                            = { repository_url = "000000000000.dkr.ecr.us-east-2.amazonaws.com/mock" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers"]
}

inputs = {
  function_name = "${local.env.name}-runner"

  # Pushed once by hand before this stack is first applied (see the README); deploys
  # replace it.
  initial_image_uri = "${dependency.registry.outputs.repository_url}:initial"

  schema_prefix         = replace(local.env.name, "-", "_")
  layer_database_names  = dependency.warehouse.outputs.database_names
  workgroup_name        = dependency.warehouse.outputs.workgroup_name
  warehouse_bucket_name = dependency.warehouse.outputs.bucket_name
  warehouse_bucket_arn  = dependency.warehouse.outputs.bucket_arn
  alert_topic_name      = local.env.alert_topic_name

  # Both environments read the ELT's production raw zone.
  raw_database_name = "data_simulator_elt_raw"
  raw_bucket_name   = "data-simulator-elt-raw-${get_aws_account_id()}"
}
