#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

STUB_BIN="${TEST_TMP_DIR}/bin"
STUB_SCRIPTS="${TEST_TMP_DIR}/scripts"
mkdir -p "${STUB_BIN}" "${STUB_SCRIPTS}"

cat > "${STUB_BIN}/tart" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "stub tart ${*}" >/dev/null
EOF
chmod +x "${STUB_BIN}/tart"

CREATE_LOG="${TEST_TMP_DIR}/create.log"
SSH_LOG="${TEST_TMP_DIR}/ssh.log"
CURSOR_LOG="${TEST_TMP_DIR}/cursor.log"
VSCODE_LOG="${TEST_TMP_DIR}/vscode.log"

cat > "${STUB_SCRIPTS}/create-dev-vm.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" > "${CREATE_LOG}"
EOF
chmod +x "${STUB_SCRIPTS}/create-dev-vm.sh"

cat > "${STUB_SCRIPTS}/ssh-dev-vm.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" > "${SSH_LOG}"
EOF
chmod +x "${STUB_SCRIPTS}/ssh-dev-vm.sh"

cat > "${STUB_SCRIPTS}/open-cursor-dev-vm.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" > "${CURSOR_LOG}"
EOF
chmod +x "${STUB_SCRIPTS}/open-cursor-dev-vm.sh"

cat > "${STUB_SCRIPTS}/open-vscode-dev-vm.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" > "${VSCODE_LOG}"
EOF
chmod +x "${STUB_SCRIPTS}/open-vscode-dev-vm.sh"

WORKTREE_DIR="${TEST_TMP_DIR}/feature-worktree"
mkdir -p "${WORKTREE_DIR}"

bootstrap_output="$(
    cd "${WORKTREE_DIR}"
    PATH="${STUB_BIN}:${PATH}" \
    REMO_TART_CREATE_DEV_VM_SCRIPT_OVERRIDE="${STUB_SCRIPTS}/create-dev-vm.sh" \
        bash "${ROOT}/scripts/tart/bootstrap-dev-vm.sh"
)"
assert_eq "" "$(cat "${CREATE_LOG}")" \
    "bootstrap should invoke the create wrapper without extra flags by default"
assert_contains "${bootstrap_output}" "scripts/tart/connect-dev-vm.sh cli remo-feature-worktree" \
    "bootstrap should print the next-step CLI connection command"

bootstrap_recreate_output="$(
    cd "${WORKTREE_DIR}"
    PATH="${STUB_BIN}:${PATH}" \
    REMO_TART_CREATE_DEV_VM_SCRIPT_OVERRIDE="${STUB_SCRIPTS}/create-dev-vm.sh" \
        bash "${ROOT}/scripts/tart/bootstrap-dev-vm.sh" --recreate --no-verify
)"
assert_eq "--recreate --no-verify" "$(cat "${CREATE_LOG}")" \
    "bootstrap should forward recreate and verify flags to the create script"
assert_contains "${bootstrap_recreate_output}" "Project VM: remo-dev" \
    "bootstrap should summarize the shared project VM"

use_output="$(
    cd "${WORKTREE_DIR}"
    PATH="${STUB_BIN}:${PATH}" \
    REMO_TART_CREATE_DEV_VM_SCRIPT_OVERRIDE="${STUB_SCRIPTS}/create-dev-vm.sh" \
        bash "${ROOT}/scripts/tart/use-worktree-dev-vm.sh" --mount-name custom-worktree --no-verify
)"
assert_eq "--mount ${WORKTREE_DIR}:custom-worktree --no-verify" "$(cat "${CREATE_LOG}")" \
    "worktree attach should reuse the shared VM and mount the current worktree"
assert_contains "${use_output}" "Mounted as: custom-worktree" \
    "worktree attach should report the selected guest mount name"

PATH="${STUB_BIN}:${PATH}" \
REMO_TART_SSH_DEV_VM_SCRIPT_OVERRIDE="${STUB_SCRIPTS}/ssh-dev-vm.sh" \
    bash "${ROOT}/scripts/tart/connect-dev-vm.sh" cli --name custom-vm --new-window custom-mount
assert_eq "--name custom-vm custom-mount" "$(cat "${SSH_LOG}")" \
    "connect cli should dispatch to ssh and ignore editor-only window flags"

PATH="${STUB_BIN}:${PATH}" \
REMO_TART_OPEN_CURSOR_DEV_VM_SCRIPT_OVERRIDE="${STUB_SCRIPTS}/open-cursor-dev-vm.sh" \
    bash "${ROOT}/scripts/tart/connect-dev-vm.sh" cursor --name custom-vm --reuse-window custom-mount
assert_eq "--name custom-vm --reuse-window custom-mount" "$(cat "${CURSOR_LOG}")" \
    "connect cursor should forward editor window flags to the Cursor launcher"

PATH="${STUB_BIN}:${PATH}" \
REMO_TART_OPEN_VSCODE_DEV_VM_SCRIPT_OVERRIDE="${STUB_SCRIPTS}/open-vscode-dev-vm.sh" \
    bash "${ROOT}/scripts/tart/connect-dev-vm.sh" vscode --new-window "${WORKTREE_DIR}"
assert_eq "--new-window ${WORKTREE_DIR}" "$(cat "${VSCODE_LOG}")" \
    "connect vscode should forward target selection to the VS Code launcher"

PATH="${STUB_BIN}:${PATH}" \
REMO_TART_SSH_DEV_VM_SCRIPT_OVERRIDE="${STUB_SCRIPTS}/ssh-dev-vm.sh" \
    bash "${ROOT}/scripts/tart/connect-dev-vm.sh" cli
assert_eq "" "$(cat "${SSH_LOG}")" \
    "connect cli should support being called without optional arguments"

PATH="${STUB_BIN}:${PATH}" \
REMO_TART_OPEN_CURSOR_DEV_VM_SCRIPT_OVERRIDE="${STUB_SCRIPTS}/open-cursor-dev-vm.sh" \
    bash "${ROOT}/scripts/tart/connect-dev-vm.sh" cursor
assert_eq "" "$(cat "${CURSOR_LOG}")" \
    "connect cursor should support being called without optional arguments"

PATH="${STUB_BIN}:${PATH}" \
REMO_TART_OPEN_VSCODE_DEV_VM_SCRIPT_OVERRIDE="${STUB_SCRIPTS}/open-vscode-dev-vm.sh" \
    bash "${ROOT}/scripts/tart/connect-dev-vm.sh" vscode
assert_eq "" "$(cat "${VSCODE_LOG}")" \
    "connect vscode should support being called without optional arguments"

mkdir -p "${WORKTREE_DIR}/.tart"
cat > "${WORKTREE_DIR}/.tart/project.sh" <<'EOF'
#!/usr/bin/env bash
EOF
mkdir -p "${WORKTREE_DIR}/.tart/packs"
touch "${WORKTREE_DIR}/.tart/packs/.keep"
mkdir -p \
    "${WORKTREE_DIR}/.tart/DerivedData" \
    "${WORKTREE_DIR}/.tart/npm-cache" \
    "${WORKTREE_DIR}/.tart/tmp" \
    "${WORKTREE_DIR}/.tart/cargo-target"

clean_output="$(
    bash "${ROOT}/scripts/tart/clean-worktree-dev-vm.sh" "${WORKTREE_DIR}"
)"
assert_contains "${clean_output}" "removed=3" \
    "default cleanup should remove only the standard generated directories"
if [[ -e "${WORKTREE_DIR}/.tart/DerivedData" || -e "${WORKTREE_DIR}/.tart/npm-cache" || -e "${WORKTREE_DIR}/.tart/tmp" ]]; then
    echo "assertion failed: default cleanup should remove derived data, npm cache, and tmp directories" >&2
    exit 1
fi
if [[ ! -d "${WORKTREE_DIR}/.tart/cargo-target" ]]; then
    echo "assertion failed: default cleanup should preserve cargo-target without --full" >&2
    exit 1
fi
if [[ ! -f "${WORKTREE_DIR}/.tart/project.sh" || ! -d "${WORKTREE_DIR}/.tart/packs" ]]; then
    echo "assertion failed: cleanup should preserve tracked Tart project configuration" >&2
    exit 1
fi

full_clean_output="$(
    bash "${ROOT}/scripts/tart/clean-worktree-dev-vm.sh" --full "${WORKTREE_DIR}"
)"
assert_contains "${full_clean_output}" "removed=1" \
    "full cleanup should remove cargo-target after the default cleanup already ran"
if [[ -e "${WORKTREE_DIR}/.tart/cargo-target" ]]; then
    echo "assertion failed: full cleanup should remove cargo-target" >&2
    exit 1
fi
