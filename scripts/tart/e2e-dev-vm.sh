#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/e2e-dev-vm.sh [--name <vm-name>] [<mount-name|host-path>] [-- <e2e-args...>]

Run the existing scripts/e2e-test.sh flow inside the running Tart VM for the
selected mounted worktree. Artifacts are saved into `<worktree>/.tart/tmp/remo-e2e/`.
EOF
}

resolve_target_host_root() {
    local vm_name target_arg manifest_path line mount_name host_path
    vm_name="$1"
    target_arg="$2"

    if [[ -d "${target_arg}" ]]; then
        remo_tart_resolve_abs_dir "${target_arg}"
        return 0
    fi

    manifest_path="$(remo_tart_mount_manifest_path "${vm_name}")"
    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        mount_name="${line%%$'\t'*}"
        host_path="${line#*$'\t'}"
        if [[ "${mount_name}" == "${target_arg}" ]]; then
            printf '%s\n' "${host_path}"
            return 0
        fi
    done < <(remo_tart_load_mount_lines "${manifest_path}")

    echo "selected mount is not recorded for ${vm_name}: ${target_arg}" >&2
    return 1
}

VM_NAME="$(remo_tart_default_vm_name)"
TARGET_ARG=""
declare -a E2E_ARGS

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_NAME="$2"
            shift 2
            ;;
        --)
            shift
            E2E_ARGS=("$@")
            break
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "${TARGET_ARG}" ]]; then
                TARGET_ARG="$1"
                shift
            else
                echo "unexpected argument: $1" >&2
                usage >&2
                exit 1
            fi
            ;;
    esac
done

if [[ -z "${TARGET_ARG}" ]]; then
    TARGET_ARG="${PWD}"
fi

remo_tart_require_cmd tart
if ! remo_tart_exec "${VM_NAME}" /usr/bin/true >/dev/null 2>&1; then
    echo "vm is not reachable: ${VM_NAME}" >&2
    echo "run scripts/tart/create-dev-vm.sh --mount \"${PWD}:$(remo_tart_mount_name_for_path "${PWD}")\" first" >&2
    exit 1
fi

GUEST_ROOT="$(remo_tart_resolve_target_guest_root "${TARGET_ARG}")"
MOUNT_NAME="$(remo_tart_resolve_target_mount_name "${TARGET_ARG}")"
HOST_ROOT="$(resolve_target_host_root "${VM_NAME}" "${TARGET_ARG}")"
ARTIFACTS_DIR="${GUEST_ROOT}/.tart/tmp/remo-e2e"
DERIVED_DATA_PATH="${GUEST_ROOT}/.tart/DerivedData/RemoExample"
GUEST_E2E_ROOT="/tmp/remo-tart-e2e/${MOUNT_NAME}"
E2E_CARGO_TARGET_DIR="${GUEST_E2E_ROOT}/cargo-target"
REMO_BIN_PATH="${E2E_CARGO_TARGET_DIR}/debug/remo"
ENV_EXPORTS="$(remo_tart_worktree_env_exports "${GUEST_ROOT}")"
E2E_CMD="$(printf '%q ' "${GUEST_ROOT}/scripts/e2e-test.sh" "${E2E_ARGS[@]}")"
FORWARD_VARS=""

if [[ -n "${SKIP_BUILD:-}" ]]; then
    FORWARD_VARS="${FORWARD_VARS}
export SKIP_BUILD=\"${SKIP_BUILD}\""
fi

if [[ -n "${DEVICE_UUID:-}" ]]; then
    FORWARD_VARS="${FORWARD_VARS}
export DEVICE_UUID=\"${DEVICE_UUID}\""
fi

SHELL_CMD="${ENV_EXPORTS}
mkdir -p \"${ARTIFACTS_DIR}\"
mkdir -p \"${E2E_CARGO_TARGET_DIR}\"
cd \"${GUEST_ROOT}\"
export ARTIFACTS_DIR=\"${ARTIFACTS_DIR}\"
export DERIVED_DATA_PATH=\"${DERIVED_DATA_PATH}\"
export CARGO_TARGET_DIR=\"${E2E_CARGO_TARGET_DIR}\"
export REMO_BIN=\"${REMO_BIN_PATH}\"
${FORWARD_VARS}
exec ${E2E_CMD}"

remo_tart_exec_script "${VM_NAME}" "${SHELL_CMD}" /bin/zsh

printf 'host_artifacts_dir=%s\n' "${HOST_ROOT}/.tart/tmp/remo-e2e"
