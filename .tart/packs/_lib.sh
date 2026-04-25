#!/usr/bin/env bash

# Helpers shared by every pack. Sourced by remo_tart.provision.build_guest_script
# before any individual pack is sourced, so pack functions can rely on these
# being defined.

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

ensure_xcode() {
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "xcodebuild not found in guest; verify the base image ships Xcode" >&2
        return 1
    fi
    xcodebuild -version >/dev/null
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

    if ! command -v npm >/dev/null 2>&1; then
        echo "npm not found; cannot install Codex CLI" >&2
        return 1
    fi

    retry_command "install Codex CLI" npm install -g @openai/codex
}

# Emit shell `export` statements for env vars every worktree session needs.
# Each pack may define `tart_pack_<name>_worktree_env_exports` to contribute
# pack-specific exports (e.g. ios DerivedData, node npm cache); we discover
# them via `declare -F` rather than re-reading project config.
remo_tart_worktree_env_exports() {
    local worktree_root tmpdir
    worktree_root="$1"
    tmpdir="${worktree_root}/.tart/tmp"
    mkdir -p "${tmpdir}"

    printf 'export REMO_TART_WORKTREE_ROOT=%q\n' "${worktree_root}"
    printf 'export TMPDIR=%q\n' "${tmpdir}"

    local export_func
    while IFS= read -r export_func; do
        [[ -n "${export_func}" ]] || continue
        "${export_func}" "${worktree_root}"
    done < <(declare -F | awk '/^declare -f tart_pack_.*_worktree_env_exports$/ {print $3}')
}
