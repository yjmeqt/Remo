#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/codex-dev-vm.sh [--name <vm-name>] [--login] [<mount-name|host-path>] [-- <codex-args...>]

Open Codex inside the running project VM at the selected mounted worktree path.

Options:
  --name <vm-name>      Override the default project VM name
  --login               Run `codex login` in the guest instead of starting Codex normally
  --                    Pass remaining arguments directly to `codex`
  -h, --help            Show this help
EOF
}

VM_NAME="$(remo_tart_default_vm_name)"
TARGET_ARG=""
LOGIN_MODE=0
declare -a CODEX_ARGS

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_NAME="$2"
            shift 2
            ;;
        --login)
            LOGIN_MODE=1
            shift
            ;;
        --)
            shift
            CODEX_ARGS=("$@")
            break
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

if [[ -d "${TARGET_ARG}" ]]; then
    MOUNT_NAME="$(remo_tart_mount_name_for_path "${TARGET_ARG}")"
else
    MOUNT_NAME="${TARGET_ARG}"
fi

GUEST_ROOT="$(remo_tart_guest_mount_path "${MOUNT_NAME}")"
ENV_EXPORTS="$(remo_tart_worktree_env_exports "${GUEST_ROOT}")"

if [[ "${LOGIN_MODE}" -eq 1 ]]; then
    CODEX_CMD="codex login"
else
    CODEX_CMD="$(printf '%q ' codex "${CODEX_ARGS[@]}")"
fi

SHELL_CMD="${ENV_EXPORTS}
mkdir -p \"${GUEST_ROOT}/.tart/tmp\"
cd \"${GUEST_ROOT}\"
if ! command -v codex >/dev/null 2>&1; then
    echo \"codex is not installed in the guest; run scripts/tart/create-dev-vm.sh first\" >&2
    exit 1
fi
exec ${CODEX_CMD}"

remo_tart_require_cmd tart
remo_tart_exec_tty "${VM_NAME}" /bin/zsh -lc "${SHELL_CMD}"
