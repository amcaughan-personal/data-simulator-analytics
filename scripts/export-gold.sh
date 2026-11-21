#!/usr/bin/env bash
# Export the gold tables as CSV files for the dashboard to read:
#
#   scripts/export-gold.sh <workgroup> <gold-database> <output-dir>
#
# Runs `select *` on each table in Athena and downloads the CSV that Athena writes as the
# query's result. The tables are small (a few hundred rows each).
set -euo pipefail

workgroup="$1"
database="$2"
out="$3"
mkdir -p "$out"

for table in $(aws glue get-tables --database-name "$database" --query 'TableList[].Name' --output text); do
  id=$(aws athena start-query-execution --work-group "$workgroup" \
    --query-execution-context Database="$database" --query-string "select * from \"$table\"" \
    --query QueryExecutionId --output text)

  while true; do
    state=$(aws athena get-query-execution --query-execution-id "$id" \
      --query QueryExecution.Status.State --output text)
    case "$state" in
      SUCCEEDED) break ;;
      FAILED | CANCELLED)
        aws athena get-query-execution --query-execution-id "$id" \
          --query QueryExecution.Status.StateChangeReason --output text >&2
        exit 1 ;;
      *) sleep 1 ;;
    esac
  done

  result=$(aws athena get-query-execution --query-execution-id "$id" \
    --query QueryExecution.ResultConfiguration.OutputLocation --output text)
  aws s3 cp --quiet "$result" "$out/$table.csv"
  echo "exported $table ($(($(wc -l < "$out/$table.csv") - 1)) rows)"
done
