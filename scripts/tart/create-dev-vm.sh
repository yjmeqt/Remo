#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/create-dev-vm.sh [options]

Create or reuse the project Tart VM, mount one or more worktrees, provision the
guest, and optionally verify the mounted primary worktree.

Options:
  --name <vm-name>                Override the default project VM name
  --base-image <image>            Override the default Tart base image
  --network <mode>                Tart network mode: shared | softnet | bridged:<iface>
  --mount <host-path[:guest-name]>  Mount a host worktree into the guest
  --recreate                      Delete and recreate the VM before booting
  --no-verify                     Skip guest verification after provisioning
  -h, --help                      Show this help
EOF
}

upsert_mount_line() {
    local new_guest new_host existing line guest host found
    new_guest="$1"
    new_host="$2"
    found=0

    for existing in "${MERGED_MOUNTS[@]:-}"; do
        guest="${existing%%$'\t'*}"
        host="${existing#*$'\t'}"
        if [[ "${guest}" == "${new_guest}" ]]; then
            MERGED_MOUNTS_UPDATED+=("${new_guest}"$'\t'"${new_host}")
            if [[ "${host}" != "${new_host}" ]]; then
                MOUNTS_CHANGED=1
            fi
            found=1
        else
            MERGED_MOUNTS_UPDATED+=("${existing}")
        fi
    done

    if [[ "${found}" -eq 0 ]]; then
        MERGED_MOUNTS_UPDATED+=("${new_guest}"$'\t'"${new_host}")
        MOUNTS_CHANGED=1
    fi
}

save_mount_manifest() {
    local manifest_path
    manifest_path="$1"
    mkdir -p "$(dirname "${manifest_path}")"
    : > "${manifest_path}"

    local line
    for line in "${MERGED_MOUNTS[@]}"; do
        printf '%s\n' "${line}" >> "${manifest_path}"
    done
}

build_dir_args() {
    local line guest host
    DIR_ARGS=()
    for line in "${MERGED_MOUNTS[@]}"; do
        guest="${line%%$'\t'*}"
        host="${line#*$'\t'}"
        DIR_ARGS+=("--dir" "${guest}:${host}")
    done
}

wait_for_guest_exec() {
    local vm_name log_path attempts
    vm_name="$1"
    log_path="$2"

    attempts=90
    while [[ "${attempts}" -gt 0 ]]; do
        if ! remo_tart_vm_is_running "${vm_name}" && [[ -f "${log_path}" ]] && [[ -s "${log_path}" ]]; then
            echo "vm failed to stay running; Tart log follows" >&2
            tail -n 120 "${log_path}" >&2
            return 1
        fi
        if remo_tart_exec "${vm_name}" /usr/bin/true >/dev/null 2>&1; then
            return 0
        fi
        attempts=$((attempts - 1))
        sleep 2
    done

    echo "guest did not become ready in time; Tart log follows" >&2
    if [[ -f "${log_path}" ]]; then
        tail -n 120 "${log_path}" >&2
    fi
    return 1
}

run_guest_script() {
    local vm_name guest_repo_root subcommand
    vm_name="$1"
    guest_repo_root="$2"
    subcommand="$3"

    local guest_script command_string
    guest_script="${guest_repo_root}/scripts/tart/provision-dev-vm.sh"
    command_string="$(printf '%q %q %q' "${guest_script}" "${subcommand}" "${guest_repo_root}")"
    remo_tart_exec_script "${vm_name}" "${command_string}"
}

run_guest_git_root_bridge() {
    local vm_name host_project_git_root guest_project_git_mount
    vm_name="$1"
    host_project_git_root="$2"
    guest_project_git_mount="$3"

    local bridge_script
    bridge_script="$(remo_tart_guest_git_root_bridge_script "${host_project_git_root}" "${guest_project_git_mount}")"
    remo_tart_exec_script "${vm_name}" "${bridge_script}"
}

VM_NAME="$(remo_tart_default_vm_name)"
BASE_IMAGE="$(remo_tart_project_base_image)"
NETWORK_MODE="$(remo_tart_project_network_mode)"
VERIFY_WORKTREE=1
RECREATE_VM=0
declare -a REQUESTED_SPECS

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_NAME="$2"
            shift 2
            ;;
        --base-image)
            BASE_IMAGE="$2"
            shift 2
            ;;
        --network)
            NETWORK_MODE="$2"
            shift 2
            ;;
        --mount)
            REQUESTED_SPECS+=("$2")
            shift 2
            ;;
        --recreate)
            RECREATE_VM=1
            shift
            ;;
        --no-verify)
            VERIFY_WORKTREE=0
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

if [[ "${#REQUESTED_SPECS[@]}" -eq 0 ]]; then
    REQUESTED_SPECS+=("${PWD}:$(remo_tart_mount_name_for_path "${PWD}")")
fi

remo_tart_require_cmd tart

STATE_DIR="$(remo_tart_host_state_dir)"
MANIFEST_PATH="$(remo_tart_mount_manifest_path "${VM_NAME}")"
LOG_PATH="$(remo_tart_vm_log_path "${VM_NAME}")"
mkdir -p "${STATE_DIR}"

declare -a MERGED_MOUNTS
declare -a EXISTING_MOUNTS
declare -a MERGED_MOUNTS_UPDATED
declare -a DIR_ARGS
declare -a RUN_ARGS
MOUNTS_CHANGED=0

stale_launchd_removed="$(remo_tart_cleanup_stale_launchd_job "${VM_NAME}")"
if [[ "${stale_launchd_removed}" -gt 0 ]]; then
    echo "removed stale launchd job for missing VM: $(remo_tart_launchd_label "${VM_NAME}")" >&2
fi

legacy_mount_removed="$(remo_tart_remove_mount_from_manifest "${MANIFEST_PATH}" "$(remo_tart_project_slug)-host-root")"
if [[ "${legacy_mount_removed}" -gt 0 ]]; then
    echo "removed ${legacy_mount_removed} legacy project-root mount entries from ${MANIFEST_PATH}" >&2
    MOUNTS_CHANGED=1
fi

pruned_mount_count="$(remo_tart_prune_mount_manifest "${MANIFEST_PATH}")"
if [[ "${pruned_mount_count}" -gt 0 ]]; then
    echo "pruned ${pruned_mount_count} stale mount entries from ${MANIFEST_PATH}" >&2
    MOUNTS_CHANGED=1
fi

while IFS= read -r line; do
    EXISTING_MOUNTS+=("${line}")
done < <(remo_tart_load_mount_lines "${MANIFEST_PATH}")

MERGED_MOUNTS=("${EXISTING_MOUNTS[@]:-}")

PRIMARY_GUEST_NAME=""
for spec in "${REQUESTED_SPECS[@]}"; do
    local_parsed_mount="$(remo_tart_parse_mount_spec "${spec}")"
    guest_name="${local_parsed_mount%%$'\t'*}"
    host_path="${local_parsed_mount#*$'\t'}"
    if [[ -z "${PRIMARY_GUEST_NAME}" ]]; then
        PRIMARY_GUEST_NAME="${guest_name}"
    fi

    MERGED_MOUNTS_UPDATED=()
    upsert_mount_line "${guest_name}" "${host_path}"
    MERGED_MOUNTS=("${MERGED_MOUNTS_UPDATED[@]}")
done

git_root_entry="$(remo_tart_git_root_mount_entry)"
git_root_guest_name="${git_root_entry%%$'\t'*}"
git_root_host_path="${git_root_entry#*$'\t'}"
MERGED_MOUNTS_UPDATED=()
upsert_mount_line "${git_root_guest_name}" "${git_root_host_path}"
MERGED_MOUNTS=("${MERGED_MOUNTS_UPDATED[@]}")

if [[ -z "${PRIMARY_GUEST_NAME}" ]]; then
    echo "no mount points configured" >&2
    exit 1
fi

save_mount_manifest "${MANIFEST_PATH}"
build_dir_args
RUN_ARGS=("--no-graphics")
network_arg="$(remo_tart_network_args "${NETWORK_MODE}")"
if [[ -n "${network_arg}" ]]; then
    RUN_ARGS+=("${network_arg}")
fi
RUN_ARGS+=("${DIR_ARGS[@]}")
RUN_ARGS+=("${VM_NAME}")

if [[ "${RECREATE_VM}" -eq 1 ]] && remo_tart_vm_exists "${VM_NAME}"; then
    remo_tart_launchd_remove "${VM_NAME}"
    if remo_tart_vm_is_running "${VM_NAME}"; then
        tart stop "${VM_NAME}"
    fi
    tart delete "${VM_NAME}"
fi

if ! remo_tart_vm_exists "${VM_NAME}"; then
    tart clone "${BASE_IMAGE}" "${VM_NAME}"
    tart set "${VM_NAME}" \
        --cpu "$(remo_tart_project_cpu_count)" \
        --memory "$(( $(remo_tart_project_memory_gb) * 1024 ))"
    MOUNTS_CHANGED=1
fi

if remo_tart_vm_is_running "${VM_NAME}" && [[ "${MOUNTS_CHANGED}" -eq 1 ]]; then
    remo_tart_launchd_remove "${VM_NAME}"
    tart stop "${VM_NAME}"
fi

if ! remo_tart_vm_is_running "${VM_NAME}"; then
    : > "${LOG_PATH}"
    remo_tart_launchd_remove "${VM_NAME}"
    remo_tart_launchd_submit_run "${VM_NAME}" "${LOG_PATH}" "${RUN_ARGS[@]}"
fi

wait_for_guest_exec "${VM_NAME}" "${LOG_PATH}"

PROJECT_GIT_ROOT_GUEST_MOUNT="$(remo_tart_guest_mount_path "${git_root_guest_name}")"
run_guest_git_root_bridge "${VM_NAME}" "${git_root_host_path}" "${PROJECT_GIT_ROOT_GUEST_MOUNT}"

PRIMARY_GUEST_ROOT="$(remo_tart_guest_mount_path "${PRIMARY_GUEST_NAME}")"
run_guest_script "${VM_NAME}" "${PRIMARY_GUEST_ROOT}" "provision"

if [[ "${VERIFY_WORKTREE}" -eq 1 ]]; then
    run_guest_script "${VM_NAME}" "${PRIMARY_GUEST_ROOT}" "verify-toolchain"
    run_guest_script "${VM_NAME}" "${PRIMARY_GUEST_ROOT}" "verify-worktree"
fi
