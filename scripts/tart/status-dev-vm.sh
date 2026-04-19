#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/status-dev-vm.sh [--name <vm-name>] [<mount-name|host-path>]

Print the current project Tart VM status as key=value pairs.
If a mount target is given, also resolve and print the selected guest mount path.
EOF
}

bool_word() {
    if [[ "$1" -eq 1 ]]; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

state_word() {
    local exists running
    exists="$1"
    running="$2"

    if [[ "${exists}" -eq 0 ]]; then
        printf 'missing\n'
    elif [[ "${running}" -eq 1 ]]; then
        printf 'running\n'
    else
        printf 'stopped\n'
    fi
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

remo_tart_require_cmd tart launchctl

EXISTS=0
RUNNING=0
LAUNCHD_JOB=0
SSH_CONFIG_PRESENT=0
SSH_KEY_PRESENT=0
LOG_PRESENT=0

MANIFEST_PATH="$(remo_tart_mount_manifest_path "${VM_NAME}")"
LOG_PATH="$(remo_tart_vm_log_path "${VM_NAME}")"
SSH_CONFIG_PATH="$(remo_tart_managed_ssh_config_path)"
SSH_KEY_PATH="$(remo_tart_ssh_key_path "${VM_NAME}")"

if remo_tart_vm_exists "${VM_NAME}"; then
    EXISTS=1
fi

if remo_tart_vm_is_running "${VM_NAME}"; then
    RUNNING=1
fi

if remo_tart_launchd_job_present "${VM_NAME}"; then
    LAUNCHD_JOB=1
fi

if [[ -f "${SSH_CONFIG_PATH}" ]]; then
    SSH_CONFIG_PRESENT=1
fi

if [[ -f "${SSH_KEY_PATH}" ]]; then
    SSH_KEY_PRESENT=1
fi

if [[ -f "${LOG_PATH}" ]]; then
    LOG_PRESENT=1
fi

declare -a MOUNT_LINES
while IFS= read -r line; do
    MOUNT_LINES+=("${line}")
done < <(remo_tart_load_mount_lines "${MANIFEST_PATH}")

SELECTED_MOUNT_PRESENT=0
for line in "${MOUNT_LINES[@]}"; do
    mount_name="${line%%$'\t'*}"
    if [[ "${mount_name}" == "${MOUNT_NAME}" ]]; then
        SELECTED_MOUNT_PRESENT=1
        break
    fi
done

printf 'vm=%s\n' "${VM_NAME}"
printf 'state=%s\n' "$(state_word "${EXISTS}" "${RUNNING}")"
printf 'exists=%s\n' "$(bool_word "${EXISTS}")"
printf 'running=%s\n' "$(bool_word "${RUNNING}")"
printf 'launchd_label=%s\n' "$(remo_tart_launchd_label "${VM_NAME}")"
printf 'launchd_job=%s\n' "$(bool_word "${LAUNCHD_JOB}")"
printf 'packs=%s\n' "$(remo_tart_enabled_packs_csv)"
printf 'ssh_alias=%s\n' "$(remo_tart_ssh_alias "${VM_NAME}")"
printf 'ssh_config_path=%s\n' "${SSH_CONFIG_PATH}"
printf 'ssh_config_present=%s\n' "$(bool_word "${SSH_CONFIG_PRESENT}")"
printf 'ssh_key_path=%s\n' "${SSH_KEY_PATH}"
printf 'ssh_key_present=%s\n' "$(bool_word "${SSH_KEY_PRESENT}")"
printf 'mount_manifest=%s\n' "${MANIFEST_PATH}"
printf 'mount_count=%s\n' "${#MOUNT_LINES[@]}"
printf 'selected_mount=%s\n' "${MOUNT_NAME}"
printf 'selected_mount_present=%s\n' "$(bool_word "${SELECTED_MOUNT_PRESENT}")"
printf 'selected_guest_root=%s\n' "${GUEST_ROOT}"
printf 'log_path=%s\n' "${LOG_PATH}"
printf 'log_present=%s\n' "$(bool_word "${LOG_PRESENT}")"

index=1
for line in "${MOUNT_LINES[@]}"; do
    mount_name="${line%%$'\t'*}"
    host_path="${line#*$'\t'}"
    printf 'mount.%s.name=%s\n' "${index}" "${mount_name}"
    printf 'mount.%s.host_path=%s\n' "${index}" "${host_path}"
    index=$((index + 1))
done
