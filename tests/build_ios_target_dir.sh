#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

STUB_BIN="${TMP_ROOT}/bin"
CUSTOM_TARGET="${TMP_ROOT}/custom-target"
LOG_DIR="${TMP_ROOT}/logs"
mkdir -p "${STUB_BIN}" "${CUSTOM_TARGET}/aarch64-apple-ios-sim/debug" "${LOG_DIR}"

touch "${CUSTOM_TARGET}/aarch64-apple-ios-sim/debug/libremo_sdk.a"

cat > "${STUB_BIN}/cargo" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "${LOG_DIR}/cargo.log"
EOF
chmod +x "${STUB_BIN}/cargo"

cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "${LOG_DIR}/xcodebuild.log"

output=""
prev=""
for arg in "\$@"; do
    if [[ "\${prev}" == "-output" ]]; then
        output="\${arg}"
        break
    fi
    prev="\${arg}"
done

if [[ -n "\${output}" ]]; then
    mkdir -p "\${output}"
fi
EOF
chmod +x "${STUB_BIN}/xcodebuild"

OUTPUT_FILE="${TMP_ROOT}/build-ios.out"
(
    cd "${ROOT}"
    PATH="${STUB_BIN}:${PATH}" CARGO_TARGET_DIR="${CUSTOM_TARGET}" ./build-ios.sh sim > "${OUTPUT_FILE}" 2>&1
)

if ! grep -Fq "build -p remo-sdk --features ios --target aarch64-apple-ios-sim" "${LOG_DIR}/cargo.log"; then
    echo "expected cargo build invocation was not recorded" >&2
    cat "${LOG_DIR}/cargo.log" >&2
    exit 1
fi

if ! grep -Fq "Done. (sim)" "${OUTPUT_FILE}"; then
    echo "build-ios.sh did not complete successfully with a custom CARGO_TARGET_DIR" >&2
    cat "${OUTPUT_FILE}" >&2
    exit 1
fi
