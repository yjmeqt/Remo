#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/doctor-dev-vm.sh [--name <vm-name>] [<mount-name|host-path>]

Run a small set of Tart VM health checks for the current project.
Exits 0 when no blocking issues are found, or 1 when issues are detected.
EOF
}

declare -a FINDINGS
ISSUE_COUNT=0
WARNING_COUNT=0

add_issue() {
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    FINDINGS+=("issue: $*")
}

add_warning() {
    WARNING_COUNT=$((WARNING_COUNT + 1))
    FINDINGS+=("warn: $*")
}

add_ok() {
    FINDINGS+=("ok: $*")
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

remo_tart_require_cmd tart launchctl

SELECTED_MOUNT_NAME="$(remo_tart_resolve_target_mount_name "${TARGET_ARG}")"
GIT_ROOT_MOUNT_NAME="$(remo_tart_git_root_mount_name)"
MANIFEST_PATH="$(remo_tart_mount_manifest_path "${VM_NAME}")"
PROJECT_CONFIG_PATH="$(remo_tart_project_config_path)"
LOG_PATH="$(remo_tart_vm_log_path "${VM_NAME}")"
SSH_CONFIG_PATH="$(remo_tart_managed_ssh_config_path)"
SSH_KEY_PATH="$(remo_tart_ssh_key_path "${VM_NAME}")"
LAUNCHD_LABEL="$(remo_tart_launchd_label "${VM_NAME}")"

VM_EXISTS=0
VM_RUNNING=0
LAUNCHD_JOB=0
SELECTED_MOUNT_PRESENT=0
GIT_ROOT_MOUNT_PRESENT=0

if [[ -f "${PROJECT_CONFIG_PATH}" ]]; then
    add_ok "project manifest exists: ${PROJECT_CONFIG_PATH}"
else
    add_issue "project manifest is missing: ${PROJECT_CONFIG_PATH}"
fi

if remo_tart_vm_exists "${VM_NAME}"; then
    VM_EXISTS=1
    add_ok "vm exists: ${VM_NAME}"
else
    add_issue "vm does not exist: ${VM_NAME}"
fi

if remo_tart_vm_is_running "${VM_NAME}"; then
    VM_RUNNING=1
    add_ok "vm is running: ${VM_NAME}"
else
    add_warning "vm is not running: ${VM_NAME}"
fi

if remo_tart_launchd_job_present "${VM_NAME}"; then
    LAUNCHD_JOB=1
    add_ok "launchd job is loaded: ${LAUNCHD_LABEL}"
else
    add_warning "launchd job is not loaded: ${LAUNCHD_LABEL}"
fi

if [[ "${VM_EXISTS}" -eq 0 && "${LAUNCHD_JOB}" -eq 1 ]]; then
    add_issue "launchd job exists for a missing VM: ${LAUNCHD_LABEL}"
fi

if [[ "${VM_RUNNING}" -eq 1 && "${LAUNCHD_JOB}" -eq 0 ]]; then
    add_warning "vm is running outside launchd management: ${VM_NAME}"
fi

if [[ -f "${MANIFEST_PATH}" ]]; then
    add_ok "mount manifest exists: ${MANIFEST_PATH}"
else
    add_issue "mount manifest is missing: ${MANIFEST_PATH}"
fi

declare -a MOUNT_LINES
while IFS= read -r line; do
    MOUNT_LINES+=("${line}")
done < <(remo_tart_load_mount_lines "${MANIFEST_PATH}")

if [[ "${#MOUNT_LINES[@]}" -eq 0 ]]; then
    add_issue "mount manifest is empty: ${MANIFEST_PATH}"
else
    add_ok "mount manifest has ${#MOUNT_LINES[@]} entries"
fi

for line in "${MOUNT_LINES[@]}"; do
    mount_name="${line%%$'\t'*}"
    host_path="${line#*$'\t'}"

    if [[ "${mount_name}" == "${SELECTED_MOUNT_NAME}" ]]; then
        SELECTED_MOUNT_PRESENT=1
    fi

    if [[ "${mount_name}" == "${GIT_ROOT_MOUNT_NAME}" ]]; then
        GIT_ROOT_MOUNT_PRESENT=1
    fi

    if [[ -d "${host_path}" ]]; then
        add_ok "mount host path exists: ${mount_name} -> ${host_path}"
    else
        add_issue "mount host path is missing: ${mount_name} -> ${host_path}"
    fi
done

if [[ "${SELECTED_MOUNT_PRESENT}" -eq 1 ]]; then
    add_ok "selected mount is recorded: ${SELECTED_MOUNT_NAME}"
else
    add_issue "selected mount is not recorded: ${SELECTED_MOUNT_NAME}"
fi

if [[ "${GIT_ROOT_MOUNT_PRESENT}" -eq 1 ]]; then
    add_ok "hidden git-root mount is recorded: ${GIT_ROOT_MOUNT_NAME}"
else
    add_issue "hidden git-root mount is missing: ${GIT_ROOT_MOUNT_NAME}"
fi

declare -a ENABLED_PACKS=()
while IFS= read -r pack_name; do
    ENABLED_PACKS+=("${pack_name}")
done < <(remo_tart_enabled_packs)

if [[ "${#ENABLED_PACKS[@]}" -eq 0 ]]; then
    add_warning "project manifest declares no Tart packs"
else
    add_ok "project manifest declares ${#ENABLED_PACKS[@]} Tart packs"
fi

for pack_name in "${ENABLED_PACKS[@]:-}"; do
    [[ -n "${pack_name}" ]] || continue
    if ! remo_tart_validate_pack_name "${pack_name}" >/dev/null 2>&1; then
        add_issue "invalid Tart pack declaration: ${pack_name}"
        continue
    fi

    pack_path="$(remo_tart_project_pack_path "${pack_name}")"
    if [[ -f "${pack_path}" ]]; then
        add_ok "pack file exists: ${pack_name} -> ${pack_path}"
    else
        add_issue "pack file is missing: ${pack_name} -> ${pack_path}"
    fi
done

if [[ -f "${SSH_CONFIG_PATH}" ]]; then
    add_ok "managed SSH config exists: ${SSH_CONFIG_PATH}"
else
    add_warning "managed SSH config is missing; run scripts/tart/prepare-remote-ssh-dev-vm.sh if you need VS Code or Cursor"
fi

if [[ -f "${SSH_KEY_PATH}" ]]; then
    add_ok "managed SSH key exists: ${SSH_KEY_PATH}"
else
    add_warning "managed SSH key is missing; run scripts/tart/prepare-remote-ssh-dev-vm.sh if you need VS Code or Cursor"
fi

if [[ -f "${LOG_PATH}" ]]; then
    add_ok "vm log exists: ${LOG_PATH}"
else
    add_warning "vm log is missing: ${LOG_PATH}"
fi

if [[ "${ISSUE_COUNT}" -eq 0 ]]; then
    printf 'status=ok\n'
else
    printf 'status=issues\n'
fi
printf 'issues=%s\n' "${ISSUE_COUNT}"
printf 'warnings=%s\n' "${WARNING_COUNT}"
printf 'vm=%s\n' "${VM_NAME}"
printf 'selected_mount=%s\n' "${SELECTED_MOUNT_NAME}"

for finding in "${FINDINGS[@]}"; do
    printf '%s\n' "${finding}"
done

if [[ "${ISSUE_COUNT}" -gt 0 ]]; then
    exit 1
fi
