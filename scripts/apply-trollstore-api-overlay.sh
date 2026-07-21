#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <source-dir>" >&2
  exit 2
fi

source_dir="$(realpath "$1")"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
overlay_root="$repo_root/overlays/trollstore-api"

if [[ ! -d "$source_dir/TrollStore" ]]; then
  echo "expected TrollStore source tree under: $source_dir" >&2
  exit 2
fi

if [[ ! -d "$overlay_root" ]]; then
  echo "overlay directory missing: $overlay_root" >&2
  exit 2
fi

echo "[info] applying TrollStore API overlay"
cp "$overlay_root/TrollStore/TSAppDelegate.m" "$source_dir/TrollStore/TSAppDelegate.m"
echo "[done] TrollStore API overlay applied"
