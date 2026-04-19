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
STALE_DIR="${TEST_TMP_DIR}/missing-worktree"
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

healthy_output="$(
    HOME="${TEST_HOME}" PATH="${STUB_BIN}:${PATH}" FAKE_TART_EXISTS=1 FAKE_TART_RUNNING=0 FAKE_LAUNCHD_PRESENT=1 \
        bash "${ROOT}/scripts/tart/doctor-dev-vm.sh" --name remo-dev "${ROOT}"
)"
assert_contains "${healthy_output}" "status=ok" \
    "doctor helper should return an ok status when only warnings are present"
assert_contains "${healthy_output}" "warnings=1" \
    "doctor helper should count warnings separately from issues"
assert_contains "${healthy_output}" "warn: vm is not running: remo-dev" \
    "doctor helper should explain a stopped VM as a warning"
assert_contains "${healthy_output}" "ok: selected mount is recorded: remo-tart-vm" \
    "doctor helper should confirm when the selected mount exists"

cat > "${TEST_HOME}/.config/remo/tart/remo-dev.mounts" <<EOF
remo-tart-vm	${STALE_DIR}
EOF

set +e
issue_output="$(
    HOME="${TEST_HOME}" PATH="${STUB_BIN}:${PATH}" FAKE_TART_EXISTS=0 FAKE_TART_RUNNING=0 FAKE_LAUNCHD_PRESENT=1 \
        bash "${ROOT}/scripts/tart/doctor-dev-vm.sh" --name remo-dev missing-mount
)"
doctor_exit=$?
set -e

if [[ "${doctor_exit}" -eq 0 ]]; then
    echo "assertion failed: doctor helper should exit non-zero when issues are present" >&2
    exit 1
fi

assert_contains "${issue_output}" "status=issues" \
    "doctor helper should surface an issues status when blocking problems are found"
assert_contains "${issue_output}" "issue: vm does not exist: remo-dev" \
    "doctor helper should report a missing VM"
assert_contains "${issue_output}" "issue: launchd job exists for a missing VM: com.remo.tart.remo-dev" \
    "doctor helper should report stale launchd ownership"
assert_contains "${issue_output}" "issue: mount host path is missing: remo-tart-vm -> ${STALE_DIR}" \
    "doctor helper should report stale mount host paths"
assert_contains "${issue_output}" "issue: selected mount is not recorded: missing-mount" \
    "doctor helper should report when the requested mount is absent from the manifest"
assert_contains "${issue_output}" "issue: hidden git-root mount is missing: remo-git-root" \
    "doctor helper should report when the required hidden git-root mount is absent"

MISSING_PROJECT_CONFIG="${TEST_TMP_DIR}/missing-project.sh"
set +e
missing_project_output="$(
    HOME="${TEST_HOME}" PATH="${STUB_BIN}:${PATH}" FAKE_TART_EXISTS=1 FAKE_TART_RUNNING=0 FAKE_LAUNCHD_PRESENT=1 \
        REMO_TART_PROJECT_CONFIG_PATH_OVERRIDE="${MISSING_PROJECT_CONFIG}" \
        bash "${ROOT}/scripts/tart/doctor-dev-vm.sh" --name remo-dev "${ROOT}"
)"
missing_project_exit=$?
set -e

if [[ "${missing_project_exit}" -eq 0 ]]; then
    echo "assertion failed: doctor helper should fail when the project manifest is missing" >&2
    exit 1
fi

assert_contains "${missing_project_output}" "issue: project manifest is missing: ${MISSING_PROJECT_CONFIG}" \
    "doctor helper should report a missing project manifest"

INVALID_PACK_CONFIG="${TEST_TMP_DIR}/invalid-pack-project.sh"
cat > "${INVALID_PACK_CONFIG}" <<'EOF'
#!/usr/bin/env bash

tart_project_packs() {
    cat <<'PACKS'
ios
missing-pack
bad/name
PACKS
}
EOF

set +e
invalid_pack_output="$(
    HOME="${TEST_HOME}" PATH="${STUB_BIN}:${PATH}" FAKE_TART_EXISTS=1 FAKE_TART_RUNNING=0 FAKE_LAUNCHD_PRESENT=1 \
        REMO_TART_PROJECT_CONFIG_PATH_OVERRIDE="${INVALID_PACK_CONFIG}" \
        bash "${ROOT}/scripts/tart/doctor-dev-vm.sh" --name remo-dev "${ROOT}"
)"
invalid_pack_exit=$?
set -e

if [[ "${invalid_pack_exit}" -eq 0 ]]; then
    echo "assertion failed: doctor helper should fail when Tart pack declarations are invalid" >&2
    exit 1
fi

assert_contains "${invalid_pack_output}" "ok: pack file exists: ios -> ${ROOT}/.tart/packs/ios.sh" \
    "doctor helper should still recognize valid Tart pack files"
assert_contains "${invalid_pack_output}" "issue: pack file is missing: missing-pack -> ${ROOT}/.tart/packs/missing-pack.sh" \
    "doctor helper should report missing Tart pack files"
assert_contains "${invalid_pack_output}" "issue: invalid Tart pack declaration: bad/name" \
    "doctor helper should report malformed Tart pack names"
