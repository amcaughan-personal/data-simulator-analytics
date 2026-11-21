# One registry for both environments: each deploy builds one image, pushes it once (from
# the dev job) and points dev, then prod, at the same digest.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infra/terragrunt/modules/registry"
}

inputs = {
  name = "data-simulator-analytics"
}
