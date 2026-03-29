#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT}/tmp/cli-release-test"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/bin"
printf '#!/usr/bin/env bash\necho "remo smoke"\n' > "${OUT_DIR}/bin/remo"
chmod +x "${OUT_DIR}/bin/remo"

bash "${ROOT}/scripts/package-cli-release.sh" \
  --version 0.0.0-test \
  --input "${OUT_DIR}/bin/remo" \
  --target aarch64-apple-darwin \
  --output-dir "${OUT_DIR}/dist"

test -f "${OUT_DIR}/dist/remo-macos-arm64.tar.gz"
tar -tzf "${OUT_DIR}/dist/remo-macos-arm64.tar.gz" | grep -qx 'remo'
test -f "${OUT_DIR}/dist/checksums.txt"
grep -q 'remo-macos-arm64.tar.gz' "${OUT_DIR}/dist/checksums.txt"
