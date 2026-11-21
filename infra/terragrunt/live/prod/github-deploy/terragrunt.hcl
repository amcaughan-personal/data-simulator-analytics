include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/terragrunt/modules/github-deploy"
}

dependency "runner" {
  config_path = "../runner"

  mock_outputs = {
    function_name = "mock-runner"
    function_arn  = "arn:aws:lambda:us-east-2:000000000000:function:mock-runner"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers"]
}

dependency "registry" {
  config_path = "../../shared/registry"

  mock_outputs = {
    repository_url = "000000000000.dkr.ecr.us-east-2.amazonaws.com/mock"
    repository_arn = "arn:aws:ecr:us-east-2:000000000000:repository/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers"]
}

inputs = {
  function_name      = dependency.runner.outputs.function_name
  function_arn       = dependency.runner.outputs.function_arn
  repository_url     = dependency.registry.outputs.repository_url
  repository_arn     = dependency.registry.outputs.repository_arn
  github_repository  = "data-simulator-analytics"
  github_environment = local.env.github_environment
  push_images        = false # the dev job builds and pushes; prod uses the same image
}
