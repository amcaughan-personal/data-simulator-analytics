#!/usr/bin/env bash
# Run dbt against one environment from your machine (or the dev container), with your AWS
# credentials:
#
#   scripts/dbt.sh dev build
#   scripts/dbt.sh dev run --select gold_card_testing
#
# Sets the variables dbt/profiles.yml reads, from the environment's names.
set -euo pipefail

env="$1"
shift
case "$env" in
  dev) name=data-simulator-analytics-dev ;;
  prod) name=data-simulator-analytics ;;
  *) echo "usage: $0 dev|prod <dbt arguments>" >&2; exit 2 ;;
esac

account=$(aws sts get-caller-identity --query Account --output text)
export DBT_SCHEMA_PREFIX="${name//-/_}"
export DBT_ATHENA_WORKGROUP="$name"
export DBT_WAREHOUSE_BUCKET="$name-warehouse-$account"

cd "$(dirname "$0")/.."
exec uv run dbt "$@" --project-dir dbt --profiles-dir dbt
