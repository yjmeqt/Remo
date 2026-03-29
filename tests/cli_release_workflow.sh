#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW="${ROOT}/.github/workflows/release.yml"

grep -q 'aarch64-apple-darwin' "${WORKFLOW}"
grep -q 'x86_64-apple-darwin' "${WORKFLOW}"
grep -q 'target/aarch64-apple-darwin/release/remo' "${WORKFLOW}"
grep -q 'target/x86_64-apple-darwin/release/remo' "${WORKFLOW}"
grep -q 'dist/cli/remo-macos-arm64.tar.gz' "${WORKFLOW}"
grep -q 'dist/cli/remo-macos-x86_64.tar.gz' "${WORKFLOW}"
grep -q 'dist/cli/checksums.txt' "${WORKFLOW}"
