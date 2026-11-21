# Everything that differs between environments. Each stack under live/dev reads this.
#
# dev is a full copy of the models that changes go through before prod, and a place to
# experiment. Both environments read the ELT's production raw tables.
locals {
  name = "data-simulator-analytics-dev"
}
