#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/use-worktree-dev-vm.sh [--no-verify] [--mount-name <name>]

Attach the current worktree to the shared project Tart VM and prepare it for
development inside the existing remo-dev environment.
EOF
}

CREATE_SCRIPT="${REMO_TART_CREATE_DEV_VM_SCRIPT_OVERRIDE:-${SCRIPT_DIR}/create-dev-vm.sh}"
MOUNT_NAME=""
VERIFY_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mount-name)
            MOUNT_NAME="$2"
            shift 2
            ;;
        --no-verify)
            VERIFY_ARGS+=("--no-verify")
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

remo_tart_require_host_tart

if [[ -z "${MOUNT_NAME}" ]]; then
    MOUNT_NAME="$(remo_tart_mount_name_for_path "${PWD}")"
else
    remo_tart_validate_mount_name "${MOUNT_NAME}"
fi

CREATE_ARGS=(--mount "${PWD}:${MOUNT_NAME}")
if [[ "${#VERIFY_ARGS[@]}" -gt 0 ]]; then
    CREATE_ARGS+=("${VERIFY_ARGS[@]}")
fi

"${CREATE_SCRIPT}" "${CREATE_ARGS[@]}"

cat <<EOF
Worktree attached to $(remo_tart_default_vm_name): ${PWD}
Mounted as: ${MOUNT_NAME}

Connect with:
  scripts/tart/connect-dev-vm.sh cli ${MOUNT_NAME}
  scripts/tart/connect-dev-vm.sh cursor ${MOUNT_NAME}
  scripts/tart/connect-dev-vm.sh vscode ${MOUNT_NAME}
EOF
