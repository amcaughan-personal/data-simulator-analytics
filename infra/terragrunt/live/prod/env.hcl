# Everything that differs between environments. Each stack under live/prod reads this.
locals {
  name               = "data-simulator-analytics"
  github_environment = "production" # deploys run in this GitHub environment

  # Email when the daily dbt run fails (the topic is from personal-infra).
  alert_topic_name = "security-alerts"
}
