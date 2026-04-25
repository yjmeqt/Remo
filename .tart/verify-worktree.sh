#!/usr/bin/env bash
set -euo pipefail
cargo check --workspace
./build-ios.sh sim
