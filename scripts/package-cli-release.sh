#!/usr/bin/env bash
set -euo pipefail

VERSION=""
INPUT=""
TARGET=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --input)
      INPUT="$2"
      shift 2
      ;;
    --target)
      TARGET="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${VERSION}" || -z "${INPUT}" || -z "${TARGET}" || -z "${OUTPUT_DIR}" ]]; then
  echo "usage: $0 --version <version> --input <path> --target <triple> --output-dir <dir>" >&2
  exit 1
fi

case "${TARGET}" in
  aarch64-apple-darwin)
    ARTIFACT_NAME="remo-macos-arm64.tar.gz"
    ;;
  x86_64-apple-darwin)
    ARTIFACT_NAME="remo-macos-x86_64.tar.gz"
    ;;
  *)
    echo "unsupported target: ${TARGET}" >&2
    exit 1
    ;;
esac

mkdir -p "${OUTPUT_DIR}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cp "${INPUT}" "${TMP_DIR}/remo"
chmod +x "${TMP_DIR}/remo"
if [[ -f "${REPO_ROOT}/LICENSE" ]]; then
  cp "${REPO_ROOT}/LICENSE" "${TMP_DIR}/LICENSE"
fi
tar -C "${TMP_DIR}" -czf "${OUTPUT_DIR}/${ARTIFACT_NAME}" remo LICENSE

if [[ -f "${OUTPUT_DIR}/checksums.txt" ]]; then
  rm "${OUTPUT_DIR}/checksums.txt"
fi

(
  cd "${OUTPUT_DIR}"
  shasum -a 256 ./*.tar.gz > checksums.txt
)

echo "${OUTPUT_DIR}/${ARTIFACT_NAME}"
