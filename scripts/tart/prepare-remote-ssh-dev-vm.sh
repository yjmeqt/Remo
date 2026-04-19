#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/prepare-remote-ssh-dev-vm.sh [--name <vm-name>]

Prepare the managed SSH alias for the running Tart development VM.
This installs a per-VM SSH key, authorizes it inside the guest, and writes the
proxy-based SSH host block used by VS Code and Cursor Remote SSH.
EOF
}

VM_NAME="$(remo_tart_default_vm_name)"

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
            echo "unexpected argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

remo_tart_require_cmd tart ssh-keygen

if ! remo_tart_vm_is_running "${VM_NAME}"; then
    echo "vm is not running: ${VM_NAME}" >&2
    exit 1
fi

remo_tart_prepare_remote_ssh "${VM_NAME}"

printf 'ssh_alias=%s\n' "$(remo_tart_ssh_alias "${VM_NAME}")"
printf 'managed_ssh_config=%s\n' "$(remo_tart_managed_ssh_config_path)"
printf 'identity_file=%s\n' "$(remo_tart_ssh_key_path "${VM_NAME}")"
