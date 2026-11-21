#!/usr/bin/env bash
# Point one environment's dbt runner at an image and wait until it's live:
#
#   scripts/deploy.sh <function-name> <image-uri@sha256:digest>
#
# The next run (scheduled or smoke test) uses it. Rolling back is re-running an earlier deploy.
set -euo pipefail

function_name="$1"
image="$2"

echo "Pointing $function_name at $image"
aws lambda update-function-code --function-name "$function_name" --image-uri "$image" \
  --query CodeSha256 --output text
aws lambda wait function-updated-v2 --function-name "$function_name"
echo "$function_name is running the new image"
