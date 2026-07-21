#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <source-dir> <subdir> <build-command> <artifact-glob> <output-dir>" >&2
  exit 2
fi

source_dir="$(realpath "$1")"
subdir="$2"
build_command="$3"
artifact_glob="$4"
output_dir="$5"

if [[ "$subdir" == /* || "$subdir" == *".."* ]]; then
  echo "invalid target subdirectory: $subdir" >&2
  exit 2
fi

if [[ "$artifact_glob" == /* || "$artifact_glob" == *".."* ]]; then
  echo "artifact glob must be relative to the project directory" >&2
  exit 2
fi

project_dir="$(realpath "$source_dir/$subdir")"
case "$project_dir/" in
  "$source_dir/"*) ;;
  *)
    echo "target subdirectory escapes source directory: $subdir" >&2
    exit 2
    ;;
esac

mkdir -p "$output_dir"
output_dir="$(realpath "$output_dir")"
export THEOS="${THEOS:-$HOME/theos}"

echo "[info] source: $source_dir"
echo "[info] project: $project_dir"
echo "[info] command: $build_command"
echo "[info] artifact glob: $artifact_glob"

cd "$project_dir"
set +e
bash -lc "$build_command" 2>&1 | tee "$output_dir/build.log"
build_status=${PIPESTATUS[0]}
set -e

if [[ $build_status -ne 0 ]]; then
  echo "[error] build command failed with status $build_status" | tee -a "$output_dir/build.log" >&2
  exit "$build_status"
fi

shopt -s nullglob globstar
artifacts=( $artifact_glob )
if [[ ${#artifacts[@]} -eq 0 ]]; then
  echo "[error] no artifacts matched: $artifact_glob" | tee -a "$output_dir/build.log" >&2
  exit 3
fi

for artifact in "${artifacts[@]}"; do
  if [[ -f "$artifact" ]]; then
    destination="$output_dir/$artifact"
    mkdir -p "$(dirname "$destination")"
    cp "$artifact" "$destination"
    echo "[artifact] $artifact"
  fi
done

if [[ $(find "$output_dir" -type f ! -name build.log | wc -l) -eq 0 ]]; then
  echo "[error] artifact glob matched no files: $artifact_glob" | tee -a "$output_dir/build.log" >&2
  exit 3
fi

{
  echo "source=$source_dir"
  echo "project=$project_dir"
  echo "command=$build_command"
  echo "artifact_glob=$artifact_glob"
  echo "theos_commit=$(git -C "$THEOS" rev-parse HEAD 2>/dev/null || echo unavailable)"
} > "$output_dir/build-summary.txt"

echo "[done] target build and artifact collection passed"
