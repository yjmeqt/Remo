#!/usr/bin/env bash
set -euo pipefail

ARCH="$(uname -m)"
case "${ARCH}" in
  arm64)
    DEFAULT_PREFIX="/opt/homebrew"
    ;;
  x86_64)
    DEFAULT_PREFIX="/usr/local"
    ;;
  *)
    DEFAULT_PREFIX="/usr/local"
    ;;
esac

PREFIX="${REMO_INSTALL_PREFIX:-${DEFAULT_PREFIX}}"
TARGET="${PREFIX}/bin/remo"

if command -v brew >/dev/null 2>&1 && brew list remo >/dev/null 2>&1; then
  echo "Remo appears to be Homebrew-managed; use: brew uninstall remo"
  exit 1
fi

if [[ -e "${TARGET}" ]]; then
  rm -f "${TARGET}"
  echo "Removed ${TARGET}"
else
  echo "No script-managed remo installation found at ${TARGET}"
fi
