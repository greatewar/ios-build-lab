#!/usr/bin/env bash
set -euo pipefail

if [[ "${RUNNER_OS:-}" != "macOS" ]]; then
  echo "TrollStore host tools require a macOS runner" >&2
  exit 2
fi

echo "[step] install TrollStore host dependencies"
brew install libarchive openssl@3 pkg-config

openssl_pkgconfig="$(brew --prefix openssl@3)/lib/pkgconfig"
export PKG_CONFIG_PATH="$openssl_pkgconfig:${PKG_CONFIG_PATH:-}"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH" >> "$GITHUB_ENV"
fi

echo "[step] dependency probes"
command -v clang
command -v brew
command -v pkg-config
pkg-config --modversion libcrypto
test -d "$(brew --prefix)/opt/libarchive/include"

echo "[done] TrollStore macOS dependencies are ready"
