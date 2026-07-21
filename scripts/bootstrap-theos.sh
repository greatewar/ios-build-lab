#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export THEOS="${THEOS:-$HOME/theos}"

echo "[info] root: $ROOT_DIR"
echo "[info] THEOS: $THEOS"

if [[ "${RUNNER_OS:-}" == "Linux" ]] && command -v apt-get >/dev/null 2>&1; then
  echo "[step] install apt dependencies"
  sudo apt-get update
  sudo apt-get install -y \
    bash \
    build-essential \
    ca-certificates \
    clang \
    curl \
    fakeroot \
    file \
    git \
    make \
    perl \
    rsync \
    unzip \
    xz-utils \
    zip \
    zstd
fi

echo "[step] install/update Theos via official installer"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"

echo "[step] basic probes"
test -d "$THEOS"
test -x "$THEOS/bin/nic.pl"
test -d "$THEOS/sdks"

echo "[step] summarize"
git -C "$THEOS" rev-parse --short HEAD
find "$THEOS/sdks" -maxdepth 1 -type d -name '*.sdk' | sort || true

echo "[done] Theos bootstrap smoke passed"
