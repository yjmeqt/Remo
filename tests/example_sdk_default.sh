#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/examples/ios/RemoExamplePackage"

default_dump="$(swift package dump-package --package-path "$PKG")"
echo "$default_dump" | jq -e '.dependencies[] | .fileSystem[]? | select(.path | endswith("/swift/RemoSwift"))' >/dev/null
echo "$default_dump" | jq -e '.targets[] | select(.name == "RemoExampleFeature") | .dependencies[] | select(.product[0] == "RemoSwift" and .product[1] == "RemoSwift")' >/dev/null

remote_dump="$(env REMO_USE_REMOTE=1 swift package dump-package --package-path "$PKG")"
echo "$remote_dump" | jq -e '.dependencies[] | .sourceControl[]? | select(.location.remote[0].urlString == "https://github.com/yjmeqt/remo-spm.git")' >/dev/null
echo "$remote_dump" | jq -e '.targets[] | select(.name == "RemoExampleFeature") | .dependencies[] | select(.product[0] == "RemoSwift" and .product[1] == "remo-spm")' >/dev/null

! rg -n "REMO_LOCAL" \
  "$ROOT/examples/ios/RemoExamplePackage/Package.swift" \
  "$ROOT/scripts/e2e-test.sh" \
  "$ROOT/examples/ios/README.md" \
  "$ROOT/AGENTS.md" \
  "$ROOT/SPEC.md"
