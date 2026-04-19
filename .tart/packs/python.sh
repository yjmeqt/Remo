#!/usr/bin/env bash

tart_pack_python_worktree_env_exports() {
    local worktree_root venv_dir pip_cache
    worktree_root="$1"
    venv_dir="${worktree_root}/.tart/venv"
    pip_cache="${worktree_root}/.tart/pip-cache"

    printf 'export VIRTUAL_ENV=%q\n' "${venv_dir}"
    printf 'export PIP_CACHE_DIR=%q\n' "${pip_cache}"
}

tart_pack_python_ensure() {
    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
        return 0
    fi

    if ! command -v brew >/dev/null 2>&1; then
        echo "python missing and Homebrew is unavailable in the guest" >&2
        return 1
    fi

    retry_command "install Python via Homebrew" brew install python
}

tart_pack_python_verify_toolchain() {
    if command -v python3 >/dev/null 2>&1; then
        python3 --version
    else
        python --version
    fi
}
