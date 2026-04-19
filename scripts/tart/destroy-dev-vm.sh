#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/destroy-dev-vm.sh [--name <vm-name>] --force

Stop and delete the project Tart VM and remove its local mount manifest.

Options:
  --name <vm-name>  Override the default project VM name
  --force           Required confirmation flag for deletion
  -h, --help        Show this help
EOF
}

VM_NAME="$(remo_tart_default_vm_name)"
FORCE_DELETE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_NAME="$2"
            shift 2
            ;;
        --force)
            FORCE_DELETE=1
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

if [[ "${FORCE_DELETE}" -ne 1 ]]; then
    echo "--force is required to delete the VM" >&2
    usage >&2
    exit 1
fi

remo_tart_require_cmd tart

if remo_tart_vm_exists "${VM_NAME}"; then
    remo_tart_launchd_remove "${VM_NAME}"
    if remo_tart_vm_is_running "${VM_NAME}"; then
        tart stop "${VM_NAME}"
    fi
    tart delete "${VM_NAME}"
fi

rm -f "$(remo_tart_mount_manifest_path "${VM_NAME}")"
rm -f "$(remo_tart_vm_log_path "${VM_NAME}")"
remo_tart_cleanup_remote_ssh_local_state "${VM_NAME}"
