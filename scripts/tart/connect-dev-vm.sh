#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
Usage: scripts/tart/connect-dev-vm.sh <cli|cursor|vscode> [options] [<mount-name|host-path>]

Open the selected mounted worktree through the preferred contributor-facing
entrypoint for the shared project Tart VM.

Options:
  --name <vm-name>     Override the default project VM name
  --new-window         Ask the editor to open a new window (cursor/vscode only)
  --reuse-window       Ask the editor to reuse the last active window (cursor/vscode only)
  -h, --help           Show this help
EOF
}

if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
fi

MODE="$1"
shift

VM_ARGS=()
EDITOR_FLAGS=()
TARGET_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_ARGS+=("--name" "$2")
            shift 2
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

case "${MODE}" in
    cli)
        CLI_SCRIPT="${REMO_TART_SSH_DEV_VM_SCRIPT_OVERRIDE:-${SCRIPT_DIR}/ssh-dev-vm.sh}"
        set --
        if [[ "${#VM_ARGS[@]}" -gt 0 ]]; then
            set -- "$@" "${VM_ARGS[@]}"
        fi
        if [[ -n "${TARGET_ARG}" ]]; then
            set -- "$@" "${TARGET_ARG}"
        fi
        exec "${CLI_SCRIPT}" "$@"
        ;;
    cursor)
        CURSOR_SCRIPT="${REMO_TART_OPEN_CURSOR_DEV_VM_SCRIPT_OVERRIDE:-${SCRIPT_DIR}/open-cursor-dev-vm.sh}"
        set --
        if [[ "${#VM_ARGS[@]}" -gt 0 ]]; then
            set -- "$@" "${VM_ARGS[@]}"
        fi
        if [[ "${#EDITOR_FLAGS[@]}" -gt 0 ]]; then
            set -- "$@" "${EDITOR_FLAGS[@]}"
        fi
        if [[ -n "${TARGET_ARG}" ]]; then
            set -- "$@" "${TARGET_ARG}"
        fi
        exec "${CURSOR_SCRIPT}" "$@"
        ;;
    vscode)
        VSCODE_SCRIPT="${REMO_TART_OPEN_VSCODE_DEV_VM_SCRIPT_OVERRIDE:-${SCRIPT_DIR}/open-vscode-dev-vm.sh}"
        set --
        if [[ "${#VM_ARGS[@]}" -gt 0 ]]; then
            set -- "$@" "${VM_ARGS[@]}"
        fi
        if [[ "${#EDITOR_FLAGS[@]}" -gt 0 ]]; then
            set -- "$@" "${EDITOR_FLAGS[@]}"
        fi
        if [[ -n "${TARGET_ARG}" ]]; then
            set -- "$@" "${TARGET_ARG}"
        fi
        exec "${VSCODE_SCRIPT}" "$@"
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo "unsupported connection mode: ${MODE}" >&2
        usage >&2
        exit 1
        ;;
esac
