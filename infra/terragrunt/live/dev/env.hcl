# Everything that differs between environments. Each stack under live/dev reads this.
#
# dev is a full copy of the models that changes go through before prod, and a place to
# experiment. Both environments read the ELT's production raw tables.
locals {
  name               = "data-simulator-analytics-dev"
  github_environment = "dev" # deploys run in this GitHub environment

  # dev failures don't email, so dev has no alarm; its logs show failures.
  alert_topic_name = null
}
