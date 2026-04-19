#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
TEST_HOME="${TEST_TMP_DIR}/home"
mkdir -p "${STUB_BIN}" "${TEST_HOME}/.config/remo/tart/ssh" "${TEST_HOME}/.ssh"

cat > "${STUB_BIN}/tart" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    list)
        if [[ "${FAKE_TART_EXISTS:-0}" == "1" ]]; then
            printf '%s\n' "remo-dev"
        fi
        ;;
    get)
        if [[ "${FAKE_TART_RUNNING:-0}" == "1" ]]; then
            cat <<JSON
{
  "Running" : true,
  "State" : "running"
}
JSON
        else
            cat <<JSON
{
  "Running" : false,
  "State" : "stopped"
}
JSON
        fi
        ;;
    *)
        echo "unexpected tart stub command: $*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "${STUB_BIN}/tart"

cat > "${STUB_BIN}/launchctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "print" && "${FAKE_LAUNCHD_PRESENT:-0}" == "1" ]]; then
    printf '%s\n' "fake launchd job"
    exit 0
fi

exit 1
EOF
chmod +x "${STUB_BIN}/launchctl"

cat > "${TEST_HOME}/.config/remo/tart/remo-dev.mounts" <<EOF
remo-tart-vm	${ROOT}
remo-git-root	/Users/yi.jiang/Developer/Remo/.git
EOF
printf 'tart log\n' > "${TEST_HOME}/.config/remo/tart/remo-dev.log"
printf 'managed ssh config\n' > "${TEST_HOME}/.config/remo/tart/ssh_config"
touch "${TEST_HOME}/.config/remo/tart/ssh/remo-dev_ed25519"

status_output="$(
    HOME="${TEST_HOME}" PATH="${STUB_BIN}:${PATH}" FAKE_TART_EXISTS=1 FAKE_TART_RUNNING=1 FAKE_LAUNCHD_PRESENT=1 \
        bash "${ROOT}/scripts/tart/status-dev-vm.sh" --name remo-dev "${ROOT}"
)"
assert_contains "${status_output}" "vm=remo-dev" \
    "status helper should print the selected VM name"
assert_contains "${status_output}" "state=running" \
    "status helper should summarize the VM state"
assert_contains "${status_output}" "exists=true" \
    "status helper should report when the VM exists"
assert_contains "${status_output}" "running=true" \
    "status helper should report when the VM is running"
assert_contains "${status_output}" "launchd_job=true" \
    "status helper should report the launchd job presence"
assert_contains "${status_output}" "ssh_key_present=true" \
    "status helper should report when the managed SSH key exists"
assert_contains "${status_output}" "packs=ios,rust,node" \
    "status helper should report the enabled pack set from the project manifest"
assert_contains "${status_output}" "mount_count=2" \
    "status helper should count mounts from the manifest"
assert_contains "${status_output}" "selected_mount=remo-tart-vm" \
    "status helper should resolve the selected mount from the host path"
assert_contains "${status_output}" "selected_mount_present=true" \
    "status helper should report when the selected mount exists in the manifest"
assert_contains "${status_output}" "selected_guest_root=/Volumes/My Shared Files/remo-tart-vm" \
    "status helper should print the guest root for the selected mount"

missing_output="$(
    HOME="${TEST_HOME}" PATH="${STUB_BIN}:${PATH}" FAKE_TART_EXISTS=0 FAKE_TART_RUNNING=0 FAKE_LAUNCHD_PRESENT=0 \
        bash "${ROOT}/scripts/tart/status-dev-vm.sh" --name remo-dev
)"
assert_contains "${missing_output}" "exists=false" \
    "status helper should report when the VM is missing"
assert_contains "${missing_output}" "state=missing" \
    "status helper should summarize a missing VM state"
assert_contains "${missing_output}" "running=false" \
    "status helper should report when the VM is not running"
assert_contains "${missing_output}" "launchd_job=false" \
    "status helper should report when the launchd job is absent"
