#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/tart/provision-dev-vm.sh <subcommand> <worktree-root>

Subcommands:
  provision         Install or verify guest-side developer dependencies
  verify-toolchain  Print toolchain versions needed by the VM workflow
  verify-worktree   Run project verification for the selected worktree
  -h, --help        Show this help
EOF
}

retry_command() {
    local description max_attempts delay attempt status
    description="$1"
    shift

    max_attempts="${REMO_TART_RETRY_ATTEMPTS:-3}"
    delay="${REMO_TART_RETRY_DELAY_SECONDS:-2}"
    attempt=1

    case "${max_attempts}" in
        ''|*[!0-9]*)
            echo "REMO_TART_RETRY_ATTEMPTS must be a positive integer" >&2
            return 1
            ;;
    esac
    if [[ "${max_attempts}" -lt 1 ]]; then
        echo "REMO_TART_RETRY_ATTEMPTS must be at least 1" >&2
        return 1
    fi

    while true; do
        if "$@"; then
            return 0
        else
            status=$?
        fi
        if [[ "${attempt}" -ge "${max_attempts}" ]]; then
            echo "${description} failed after ${attempt}/${max_attempts} attempts" >&2
            return "${status}"
        fi

        echo "${description} failed on attempt ${attempt}/${max_attempts}; retrying in ${delay}s" >&2
        sleep "${delay}"
        attempt=$((attempt + 1))
    done
}

ensure_worktree_dirs() {
    local worktree_root
    worktree_root="$1"
    mkdir -p \
        "${worktree_root}/.tart/DerivedData" \
        "${worktree_root}/.tart/cargo-target" \
        "${worktree_root}/.tart/go-build" \
        "${worktree_root}/.tart/go-mod" \
        "${worktree_root}/.tart/npm-cache" \
        "${worktree_root}/.tart/pip-cache" \
        "${worktree_root}/.tart/tmp"
}

apply_worktree_env() {
    local worktree_root
    worktree_root="$1"
    ensure_worktree_dirs "${worktree_root}"
    eval "$(remo_tart_worktree_env_exports "${worktree_root}")"
    export PATH="${HOME}/.cargo/bin:${PATH}"
}

rust_targets_from_toolchain() {
    local toolchain_file
    toolchain_file="$1"

    awk '
        /targets = \[/ { in_targets = 1; next }
        in_targets && /\]/ { in_targets = 0; next }
        in_targets {
            gsub(/[",]/, "", $0)
            gsub(/[[:space:]]/, "", $0)
            if (length($0) > 0) print $0
        }
    ' "${toolchain_file}"
}

ensure_xcode() {
    remo_tart_require_cmd xcodebuild
    xcodebuild -version >/dev/null
}

ensure_rustup() {
    if command -v rustup >/dev/null 2>&1; then
        return 0
    fi

    remo_tart_require_cmd curl
    retry_command \
        "install rustup" \
        /bin/bash -lc "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
}

ensure_rust_targets() {
    local worktree_root toolchain_file target
    worktree_root="$1"
    toolchain_file="${worktree_root}/rust-toolchain.toml"

    if [[ ! -f "${toolchain_file}" ]]; then
        echo "missing rust-toolchain.toml at ${toolchain_file}" >&2
        return 1
    fi

    while IFS= read -r target; do
        [[ -n "${target}" ]] || continue
        retry_command "install Rust target ${target}" rustup target add "${target}"
    done < <(rust_targets_from_toolchain "${toolchain_file}")
}

ensure_cbindgen() {
    if command -v cbindgen >/dev/null 2>&1; then
        return 0
    fi

    remo_tart_require_cmd cargo
    retry_command "install cbindgen" cargo install cbindgen --locked
}

ensure_node_and_npm() {
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        return 0
    fi

    if ! command -v brew >/dev/null 2>&1; then
        echo "node/npm missing and Homebrew is unavailable in the guest" >&2
        return 1
    fi

    retry_command "install node via Homebrew" brew install node
}

ensure_codex() {
    if command -v codex >/dev/null 2>&1; then
        return 0
    fi

    remo_tart_require_cmd npm
    retry_command "install Codex CLI" npm install -g @openai/codex
}

run_make_setup() {
    local worktree_root
    worktree_root="$1"
    remo_tart_require_cmd make
    (
        cd "${worktree_root}"
        make setup
    )
}

run_project_command_block() {
    local hook_name worktree_root command_block
    hook_name="$1"
    worktree_root="$2"

    remo_tart_load_project_config
    if ! declare -F "${hook_name}" >/dev/null 2>&1; then
        return 0
    fi

    command_block="$("${hook_name}")"
    [[ -n "${command_block}" ]] || return 0

    (
        cd "${worktree_root}"
        eval "${command_block}"
    )
}

run_provision() {
    local worktree_root pack_name ensure_func
    worktree_root="$1"

    apply_worktree_env "${worktree_root}"
    remo_tart_load_enabled_project_packs

    while IFS= read -r pack_name; do
        [[ -n "${pack_name}" ]] || continue
        ensure_func="tart_pack_${pack_name}_ensure"
        if declare -F "${ensure_func}" >/dev/null 2>&1; then
            "${ensure_func}" "${worktree_root}"
        fi
    done < <(remo_tart_enabled_packs)

    run_project_command_block tart_project_provision "${worktree_root}"
}

run_verify_toolchain() {
    local worktree_root pack_name verify_func
    worktree_root="$1"

    apply_worktree_env "${worktree_root}"
    remo_tart_load_enabled_project_packs

    while IFS= read -r pack_name; do
        [[ -n "${pack_name}" ]] || continue
        verify_func="tart_pack_${pack_name}_verify_toolchain"
        if declare -F "${verify_func}" >/dev/null 2>&1; then
            "${verify_func}"
        fi
    done < <(remo_tart_enabled_packs)
}

run_verify_worktree() {
    local worktree_root
    worktree_root="$1"

    apply_worktree_env "${worktree_root}"
    run_project_command_block tart_project_verify_worktree "${worktree_root}"
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi

SUBCOMMAND="${1:-}"
WORKTREE_ROOT="${2:-}"

case "${SUBCOMMAND}" in
    -h|--help|"")
        usage
        exit 0
        ;;
esac

if [[ -z "${WORKTREE_ROOT}" ]]; then
    echo "missing worktree root argument" >&2
    usage >&2
    exit 1
fi

case "${SUBCOMMAND}" in
    provision)
        run_provision "${WORKTREE_ROOT}"
        ;;
    verify-toolchain)
        run_verify_toolchain "${WORKTREE_ROOT}"
        ;;
    verify-worktree)
        run_verify_worktree "${WORKTREE_ROOT}"
        ;;
    *)
        echo "unknown subcommand: ${SUBCOMMAND}" >&2
        usage >&2
        exit 1
        ;;
esac
