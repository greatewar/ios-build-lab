#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <source-dir> <victim-ipa-url> [victim-team-id]" >&2
  exit 2
fi

source_dir="$(realpath "$1")"
victim_ipa_url="$2"
victim_team_id="${3:-}"
victim_dir="$source_dir/Victim"
victim_ipa_path="$victim_dir/InstallerVictim.ipa"

if [[ ! -d "$victim_dir" ]]; then
  echo "Victim directory not found: $victim_dir" >&2
  exit 2
fi

echo "[info] downloading victim ipa"
echo "[info] source: $victim_ipa_url"
curl -L --fail --retry 3 --retry-all-errors "$victim_ipa_url" -o "$victim_ipa_path"

if [[ ! -s "$victim_ipa_path" ]]; then
  echo "[error] downloaded victim ipa is empty" >&2
  exit 3
fi

python_bin="$(command -v python3 || command -v python || true)"
if [[ -z "$python_bin" ]]; then
  echo "[error] python is required to validate victim ipa" >&2
  exit 3
fi

"$python_bin" - "$victim_ipa_path" <<'PY'
import sys
import zipfile

ipa_path = sys.argv[1]
with zipfile.ZipFile(ipa_path) as archive:
    names = archive.namelist()
    has_payload = any(name.startswith("Payload/") for name in names)
    has_app = any(name.startswith("Payload/") and ".app/" in name for name in names)

if not has_payload or not has_app:
    raise SystemExit("victim ipa must contain Payload/<App>.app/")
PY

if [[ -n "$victim_team_id" ]]; then
  echo "[info] generating victim.p12 for team: $victim_team_id"
  (
    cd "$victim_dir"
    bash ./make_cert.sh "$victim_team_id"
  )

  if [[ ! -s "$victim_dir/victim.p12" ]]; then
    echo "[error] victim.p12 was not generated" >&2
    exit 3
  fi
else
  echo "[info] victim_team_id not provided, iOS 15 installer build will be skipped"
fi

echo "[done] victim inputs are ready"
