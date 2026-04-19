#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$(mktemp)"
trap 'rm -f "${OUTPUT}"' EXIT

bash "${ROOT}/scripts/render-homebrew-formula.sh" \
  --version 5.0.0 \
  --repo yjmeqt/Remo \
  --arm64-sha 1111111111111111111111111111111111111111111111111111111111111111 \
  --x86-sha 2222222222222222222222222222222222222222222222222222222222222222 \
  > "${OUTPUT}"

grep -q 'class Remo < Formula' "${OUTPUT}"
grep -q 'version "5.0.0"' "${OUTPUT}"
grep -q 'remo-macos-arm64.tar.gz' "${OUTPUT}"
grep -q 'remo-macos-x86_64.tar.gz' "${OUTPUT}"
grep -q '1111111111111111111111111111111111111111111111111111111111111111' "${OUTPUT}"
grep -q '2222222222222222222222222222222222222222222222222222222222222222' "${OUTPUT}"
