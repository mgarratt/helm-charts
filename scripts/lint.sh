#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "[lint] helm"
chart_dirs=()
while IFS= read -r -d '' chart_file; do
  chart_dirs+=("$(dirname "$chart_file")")
done < <(find charts -mindepth 2 -maxdepth 2 -type f -name Chart.yaml -print0 2>/dev/null || true)

if [[ ${#chart_dirs[@]} -eq 0 ]]; then
  echo "[lint] no charts found"
  exit 0
fi

for d in "${chart_dirs[@]}"; do
  if command -v helm >/dev/null 2>&1; then
    helm lint "$d"
  elif command -v mise >/dev/null 2>&1; then
    mise exec -- helm lint "$d"
  else
    echo "[lint] helm is required (install via mise)" >&2
    exit 127
  fi
done
