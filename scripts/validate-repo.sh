#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[step] check required paths"
for path in .github/workflows docs scripts README.md; do
  [[ -e "$path" ]] || { echo "missing: $path" >&2; exit 1; }
done

echo "[step] bash syntax check"
while IFS= read -r file; do
  bash -n "$file"
done < <(find scripts -type f -name '*.sh' | sort)

echo "[done] repository validation passed"
