#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/scripts/tart/provision-dev-vm.sh"

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "${expected}" != "${actual}" ]]; then
        echo "assertion failed: ${message}" >&2
        echo "expected: ${expected}" >&2
        echo "actual:   ${actual}" >&2
        exit 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "${haystack}" != *"${needle}"* ]]; then
        echo "assertion failed: ${message}" >&2
        echo "missing needle: ${needle}" >&2
        exit 1
    fi
}

TEST_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_TMP_DIR}"' EXIT

source "${ROOT}/.tart/packs/ios.sh"
source "${ROOT}/.tart/packs/rust.sh"
source "${ROOT}/.tart/packs/node.sh"
source "${ROOT}/.tart/packs/go.sh"
source "${ROOT}/.tart/packs/python.sh"

WORKTREE_ROOT="${TEST_TMP_DIR}/worktree"
mkdir -p "${WORKTREE_ROOT}"

assert_contains "$(tart_pack_ios_worktree_env_exports "${WORKTREE_ROOT}")" ".tart/DerivedData" \
    "ios pack should export a worktree-local DerivedData path"
assert_contains "$(tart_pack_rust_worktree_env_exports "${WORKTREE_ROOT}")" ".tart/cargo-target" \
    "rust pack should export a worktree-local cargo target path"
assert_contains "$(tart_pack_node_worktree_env_exports "${WORKTREE_ROOT}")" ".tart/npm-cache" \
    "node pack should export a worktree-local npm cache path"
assert_contains "$(tart_pack_go_worktree_env_exports "${WORKTREE_ROOT}")" ".tart/go-build" \
    "go pack should export a worktree-local Go build cache path"
assert_contains "$(tart_pack_go_worktree_env_exports "${WORKTREE_ROOT}")" ".tart/go-mod" \
    "go pack should export a worktree-local Go module cache path"
assert_contains "$(tart_pack_python_worktree_env_exports "${WORKTREE_ROOT}")" ".tart/venv" \
    "python pack should export a worktree-local virtualenv path"
assert_contains "$(tart_pack_python_worktree_env_exports "${WORKTREE_ROOT}")" ".tart/pip-cache" \
    "python pack should export a worktree-local pip cache path"

worktree_env_exports="$(remo_tart_worktree_env_exports "${WORKTREE_ROOT}")"
assert_contains "${worktree_env_exports}" ".tart/DerivedData" \
    "current project worktree exports should include ios pack state"
assert_contains "${worktree_env_exports}" ".tart/cargo-target" \
    "current project worktree exports should include rust pack state"
assert_contains "${worktree_env_exports}" ".tart/npm-cache" \
    "current project worktree exports should include node pack state"

remo_tart_load_project_config

PROVISION_LOG="${TEST_TMP_DIR}/provision.log"
: > "${PROVISION_LOG}"
tart_pack_ios_ensure() { printf 'ios\n' >> "${PROVISION_LOG}"; }
tart_pack_rust_ensure() { printf 'rust\n' >> "${PROVISION_LOG}"; }
tart_pack_node_ensure() { printf 'node\n' >> "${PROVISION_LOG}"; }
REMO_TART_PACK_LOADED_ios=1
REMO_TART_PACK_LOADED_rust=1
REMO_TART_PACK_LOADED_node=1
tart_project_provision() {
    cat <<EOF
printf '%s\n' project-provision >> '${PROVISION_LOG}'
EOF
}
run_provision "${WORKTREE_ROOT}"
assert_eq $'ios\nrust\nnode\nproject-provision' "$(cat "${PROVISION_LOG}")" \
    "pack-driven provisioning should run enabled pack ensure hooks before the project provision hook"

VERIFY_LOG="${TEST_TMP_DIR}/verify.log"
: > "${VERIFY_LOG}"
tart_project_verify_worktree() {
    cat <<EOF
printf '%s\n' project-verify >> '${VERIFY_LOG}'
EOF
}
run_verify_worktree "${WORKTREE_ROOT}"
assert_eq "project-verify" "$(cat "${VERIFY_LOG}")" \
    "pack-driven worktree verification should run the project verify hook"

cat > "${TEST_TMP_DIR}/flakey-success" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
COUNTER_FILE="$1"
CURRENT_COUNT="$(cat "${COUNTER_FILE}")"
CURRENT_COUNT=$((CURRENT_COUNT + 1))
printf '%s' "${CURRENT_COUNT}" > "${COUNTER_FILE}"
if [[ "${CURRENT_COUNT}" -lt 3 ]]; then
    exit 7
fi
EOF
chmod +x "${TEST_TMP_DIR}/flakey-success"

cat > "${TEST_TMP_DIR}/always-fail" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 9
EOF
chmod +x "${TEST_TMP_DIR}/always-fail"

COUNTER_FILE="${TEST_TMP_DIR}/counter"
printf '0' > "${COUNTER_FILE}"
retry_output="$(
    REMO_TART_RETRY_ATTEMPTS=3 REMO_TART_RETRY_DELAY_SECONDS=0 \
        retry_command "flakey command" "${TEST_TMP_DIR}/flakey-success" "${COUNTER_FILE}" 2>&1
)"
assert_eq "3" "$(cat "${COUNTER_FILE}")" \
    "retry helper should keep retrying until the command succeeds"
assert_contains "${retry_output}" "flakey command failed on attempt 1/3; retrying in 0s" \
    "retry helper should report retry attempts"

if failure_output="$(
    REMO_TART_RETRY_ATTEMPTS=2 REMO_TART_RETRY_DELAY_SECONDS=0 \
        retry_command "always failing command" "${TEST_TMP_DIR}/always-fail" 2>&1
)"; then
    echo "assertion failed: retry helper should eventually fail when the command never succeeds" >&2
    exit 1
fi
assert_contains "${failure_output}" "always failing command failed after 2/2 attempts" \
    "retry helper should report the final failed attempt count"
