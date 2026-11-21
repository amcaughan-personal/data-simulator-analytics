#!/usr/bin/env bash
# Build the dbt runner's image (see Dockerfile):
#
#   scripts/build-image.sh <tag>
#
# Exports the runtime requirements from uv.lock (with hashes) for the image to install.
set -euo pipefail

tag="$1"
cd "$(dirname "$0")/.."
mkdir -p build
uv export --frozen --no-dev --no-emit-project --format requirements.txt --quiet > build/requirements.txt
docker build --platform linux/amd64 --tag "$tag" .
