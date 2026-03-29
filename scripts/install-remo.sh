#!/usr/bin/env bash
set -euo pipefail

VERSION="latest"
BASE_URL="${REMO_RELEASE_BASE_URL:-https://github.com/yjmeqt/Remo/releases/download}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

ARCH="$(uname -m)"
case "${ARCH}" in
  arm64)
    ARTIFACT="remo-macos-arm64.tar.gz"
    DEFAULT_PREFIX="/opt/homebrew"
    ;;
  x86_64)
    ARTIFACT="remo-macos-x86_64.tar.gz"
    DEFAULT_PREFIX="/usr/local"
    ;;
  *)
    echo "unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

PREFIX="${REMO_INSTALL_PREFIX:-${DEFAULT_PREFIX}}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

if [[ "${VERSION}" == "latest" ]]; then
  if [[ "${BASE_URL}" == file://* ]]; then
    RELEASE_PATH="${BASE_URL}/latest/download"
  else
    RELEASE_PATH="${BASE_URL%/download}/latest/download"
  fi
else
  RELEASE_PATH="${BASE_URL}/v${VERSION}"
fi

ASSET_URL="${RELEASE_PATH}/${ARTIFACT}"
CHECKSUM_URL="${RELEASE_PATH}/checksums.txt"

echo "Downloading ${ASSET_URL}"
curl -fsSL "${ASSET_URL}" -o "${TMP_DIR}/${ARTIFACT}"
curl -fsSL "${CHECKSUM_URL}" -o "${TMP_DIR}/checksums.txt"

(
  cd "${TMP_DIR}"
  shasum -a 256 -c checksums.txt --ignore-missing
)

mkdir -p "${PREFIX}/bin"
tar -xzf "${TMP_DIR}/${ARTIFACT}" -C "${TMP_DIR}"
install -m 0755 "${TMP_DIR}/remo" "${PREFIX}/bin/remo"

echo "Installed remo to ${PREFIX}/bin/remo"
