#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/ssh-dev-vm.sh [--name <vm-name>] [<mount-name|host-path>]

Open an interactive shell in the running project VM at the selected mounted
worktree path. If no mount target is given, the current working directory is
used to derive the mount name.
EOF
}

VM_NAME="$(remo_tart_default_vm_name)"
TARGET_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            TARGET_ARG="$1"
            shift
            ;;
    esac
done

if [[ -z "${TARGET_ARG}" ]]; then
    TARGET_ARG="${PWD}"
fi

MOUNT_NAME="$(remo_tart_resolve_target_mount_name "${TARGET_ARG}")"
GUEST_ROOT="$(remo_tart_resolve_target_guest_root "${TARGET_ARG}")"
ENV_EXPORTS="$(remo_tart_worktree_env_exports "${GUEST_ROOT}")"
SHELL_CMD="${ENV_EXPORTS}
mkdir -p \"${GUEST_ROOT}/.tart/tmp\"
cd \"${GUEST_ROOT}\"
exec /bin/zsh -il"

remo_tart_require_cmd tart
if ! remo_tart_vm_is_running "${VM_NAME}"; then
    echo "vm is not running: ${VM_NAME}" >&2
    exit 1
fi

remo_tart_exec_tty "${VM_NAME}" /bin/zsh -lc "${SHELL_CMD}"
