#!/usr/bin/env bash
# Run the dbt runner once, as the daily schedule does (freshness, then build and test
# everything), and fail if the run fails:
#
#   scripts/smoke-test.sh <function-name>
#
# A run takes a couple of minutes. The function runs one at a time, so if a scheduled run is
# in progress, wait and try again.
set -euo pipefail

function_name="$1"
out=$(mktemp)

for attempt in 1 2 3 4 5; do
  if error=$(aws lambda invoke --function-name "$function_name" --payload '{}' \
    --cli-binary-format raw-in-base64-out --cli-read-timeout 900 \
    --query FunctionError --output text "$out" 2>&1); then
    break
  fi
  if [[ "$error" != *TooManyRequestsException* || "$attempt" == 5 ]]; then
    echo "$error" >&2
    exit 1
  fi
  echo "A scheduled run is in progress; retrying in 60 s"
  sleep 60
done

if [[ "$error" != "None" ]]; then
  echo "The run failed ($error); its logs say which nodes:" >&2
  cat "$out" >&2
  exit 1
fi
echo "dbt: $(cat "$out")"
