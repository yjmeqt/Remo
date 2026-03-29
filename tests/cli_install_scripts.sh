#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/fixtures/v0.0.0-test" "${TMP_DIR}/prefix/bin"
printf '#!/usr/bin/env bash\necho "remo fixture"\n' > "${TMP_DIR}/fixtures/remo"
chmod +x "${TMP_DIR}/fixtures/remo"
tar -C "${TMP_DIR}/fixtures" -czf "${TMP_DIR}/fixtures/v0.0.0-test/remo-macos-arm64.tar.gz" remo
(cd "${TMP_DIR}/fixtures/v0.0.0-test" && shasum -a 256 remo-macos-arm64.tar.gz > checksums.txt)

REMO_INSTALL_PREFIX="${TMP_DIR}/prefix" \
REMO_RELEASE_BASE_URL="file://${TMP_DIR}/fixtures" \
bash "${ROOT}/scripts/install-remo.sh" --version 0.0.0-test

test -x "${TMP_DIR}/prefix/bin/remo"

REMO_INSTALL_PREFIX="${TMP_DIR}/prefix" \
bash "${ROOT}/scripts/uninstall-remo.sh"

test ! -e "${TMP_DIR}/prefix/bin/remo"
