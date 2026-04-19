#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/clean-worktree-dev-vm.sh [--name <vm-name>] [--full] [<mount-name|host-path>]

Remove generated Tart cache directories for the selected worktree without
touching tracked .tart project configuration.

Default cleanup removes:
  .tart/DerivedData
  .tart/npm-cache
  .tart/tmp

Use --full to additionally remove:
  .tart/cargo-target
EOF
}

VM_NAME="$(remo_tart_default_vm_name)"
FULL_CLEAN=0
TARGET_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_NAME="$2"
            shift 2
            ;;
        --full)
            FULL_CLEAN=1
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

WORKTREE_ROOT="$(remo_tart_resolve_target_host_root "${VM_NAME}" "${TARGET_ARG}")"
TART_ROOT="${WORKTREE_ROOT}/.tart"

declare -a CLEAN_DIRS=(
    "${TART_ROOT}/DerivedData"
    "${TART_ROOT}/npm-cache"
    "${TART_ROOT}/tmp"
)

if [[ "${FULL_CLEAN}" -eq 1 ]]; then
    CLEAN_DIRS+=("${TART_ROOT}/cargo-target")
fi

removed_count=0
for clean_dir in "${CLEAN_DIRS[@]}"; do
    if [[ -e "${clean_dir}" ]]; then
        rm -rf "${clean_dir}"
        removed_count=$((removed_count + 1))
    fi
done

printf 'worktree=%s\n' "${WORKTREE_ROOT}"
printf 'removed=%s\n' "${removed_count}"
printf 'preserved=%s\n' "${TART_ROOT}/project.sh"
printf 'preserved=%s\n' "${TART_ROOT}/packs"
