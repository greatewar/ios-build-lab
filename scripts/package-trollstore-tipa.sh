#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <trollstore-tar> <output-tipa>" >&2
  exit 2
fi

input_tar="$(realpath "$1")"
output_tipa="$2"

if [[ ! -f "$input_tar" ]]; then
  echo "input tar not found: $input_tar" >&2
  exit 2
fi

output_dir="$(dirname "$output_tipa")"
mkdir -p "$output_dir"
output_tipa="$(realpath "$output_dir")/$(basename "$output_tipa")"

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

zip_bin="$(command -v zip || true)"
python_bin="$(command -v python3 || true)"
if [[ "$python_bin" == *"/WindowsApps/"* || "$python_bin" == *"/WINDOWS/WindowsApps/"* || "$python_bin" == *"/WINDOWSAPPS/"* ]]; then
  python_bin=""
fi
if [[ -z "$python_bin" ]]; then
  python_bin="$(command -v py.exe || command -v py || command -v python || true)"
fi
if [[ -z "$zip_bin" && -z "$python_bin" ]]; then
  echo "neither zip nor python was found for packaging $input_tar" >&2
  exit 3
fi

mkdir -p "$work_dir/Payload"
tar -xzf "$input_tar" -C "$work_dir/Payload"

app_dir="$(find "$work_dir/Payload" -maxdepth 1 -type d -name '*.app' | head -n 1)"
if [[ -z "$app_dir" ]]; then
  echo "no .app found after extracting $input_tar" >&2
  exit 3
fi

(
  cd "$work_dir"
  if [[ -n "$zip_bin" ]]; then
    "$zip_bin" -qry "$output_tipa" Payload
  else
    python_args=()
    if [[ "$(basename "$python_bin")" == "py" || "$(basename "$python_bin")" == "py.exe" ]]; then
      python_args=(-3 -)
    else
      python_args=(-)
    fi

    "$python_bin" "${python_args[@]}" "$output_tipa" <<'PY'
import os
import sys
import zipfile

output_path = sys.argv[1]
with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk("Payload"):
        for file_name in files:
            full_path = os.path.join(root, file_name)
            zf.write(full_path, full_path)
PY
  fi
)

echo "[done] created tipa: $output_tipa"
