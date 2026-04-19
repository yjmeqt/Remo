#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

EDITOR_CMD="${1:-}"
EDITOR_LABEL="${2:-}"
if [[ -z "${EDITOR_CMD}" || -z "${EDITOR_LABEL}" ]]; then
    echo "usage: open-editor-dev-vm.sh <editor-cmd> <editor-label> [args...]" >&2
    exit 1
fi
shift 2

usage() {
    cat <<EOF
Usage: scripts/tart/open-${EDITOR_LABEL}-dev-vm.sh [--name <vm-name>] [--print-only] [--new-window|--reuse-window] [<mount-name|host-path>]

Prepare a managed SSH alias that proxies through tart exec, then open the
selected mounted worktree in ${EDITOR_LABEL} using Remote SSH.

Options:
  --name <vm-name>        Override the default project VM name
  --print-only            Print the resolved remote command instead of launching the editor
  --new-window            Ask the editor to open a new window
  --reuse-window          Ask the editor to reuse the last active window
  -h, --help              Show this help
EOF
}

VM_NAME="$(remo_tart_default_vm_name)"
TARGET_ARG=""
PRINT_ONLY=0
EDITOR_FLAGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_NAME="$2"
            shift 2
            ;;
        --print-only)
            PRINT_ONLY=1
            shift
            ;;
        --new-window|-n)
            EDITOR_FLAGS+=("--new-window")
            shift
            ;;
        --reuse-window|-r)
            EDITOR_FLAGS+=("--reuse-window")
            shift
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

MOUNT_NAME="$(remo_tart_resolve_target_mount_name "${TARGET_ARG}")"
GUEST_ROOT="$(remo_tart_resolve_target_guest_root "${TARGET_ARG}")"

remo_tart_require_cmd tart "${EDITOR_CMD}"

if ! remo_tart_vm_is_running "${VM_NAME}"; then
    echo "vm is not running: ${VM_NAME}" >&2
    exit 1
fi

SSH_ALIAS="$(remo_tart_ssh_alias "${VM_NAME}")"
AUTHORITY="$(remo_tart_remote_alias_authority "${SSH_ALIAS}")"
OPEN_CMD=("${EDITOR_CMD}")
if [[ "${#EDITOR_FLAGS[@]}" -gt 0 ]]; then
    OPEN_CMD+=("${EDITOR_FLAGS[@]}")
fi
OPEN_CMD+=(--remote "${AUTHORITY}" "${GUEST_ROOT}")

if [[ "${PRINT_ONLY}" -eq 1 ]]; then
    printf 'editor=%s\n' "${EDITOR_CMD}"
    printf 'vm=%s\n' "${VM_NAME}"
    printf 'ssh_alias=%s\n' "${SSH_ALIAS}"
    printf 'authority=%s\n' "${AUTHORITY}"
    printf 'guest_root=%s\n' "${GUEST_ROOT}"
    printf 'managed_ssh_config=%s\n' "$(remo_tart_managed_ssh_config_path)"
    printf 'command='
    printf '%q ' "${OPEN_CMD[@]}"
    printf '\n'
    exit 0
fi

remo_tart_prepare_remote_ssh "${VM_NAME}"

exec "${OPEN_CMD[@]}"
