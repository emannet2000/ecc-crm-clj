#!/usr/bin/env bash
# Run from a checkout where the repository root is writable.
set -euo pipefail
api_dir=$(cd "$(dirname "$0")/.." && pwd)
repo_dir=${1:-"$api_dir/.."}
if [[ ! -f "$repo_dir/api/ecc-crm-api.cabal" ]]; then
  echo 'Usage: bash api/scripts/install-ci.sh /path/to/repository-root' >&2
  exit 1
fi
mkdir -p "$repo_dir/.github/workflows"
cp "$api_dir/.github/workflows/ci.yml" "$repo_dir/.github/workflows/api-quality.yml"
echo 'Installed api-quality.yml alongside the existing release/security workflow.'
