#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/bootstrap-dev-vm.sh [--recreate] [--no-verify]

Bootstrap the shared project Tart VM for the current worktree after cloning
the Remo repository for the first time.
EOF
}

CREATE_SCRIPT="${REMO_TART_CREATE_DEV_VM_SCRIPT_OVERRIDE:-${SCRIPT_DIR}/create-dev-vm.sh}"
RECREATE_VM=0
VERIFY_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --recreate)
            RECREATE_VM=1
            shift
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

CREATE_ARGS=()
if [[ "${RECREATE_VM}" -eq 1 ]]; then
    CREATE_ARGS+=("--recreate")
fi
if [[ "${#VERIFY_ARGS[@]}" -gt 0 ]]; then
    CREATE_ARGS+=("${VERIFY_ARGS[@]}")
fi

if [[ "${#CREATE_ARGS[@]}" -gt 0 ]]; then
    "${CREATE_SCRIPT}" "${CREATE_ARGS[@]}"
else
    "${CREATE_SCRIPT}"
fi

mount_name="$(remo_tart_mount_name_for_path "${PWD}")"
cat <<EOF
Bootstrap complete for worktree: ${PWD}
Project VM: $(remo_tart_default_vm_name)
Mounted as: ${mount_name}

Next steps:
  scripts/tart/connect-dev-vm.sh cli ${mount_name}
  scripts/tart/connect-dev-vm.sh cursor ${mount_name}
  scripts/tart/connect-dev-vm.sh vscode ${mount_name}
EOF
