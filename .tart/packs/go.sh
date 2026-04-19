#!/usr/bin/env bash

tart_pack_go_worktree_env_exports() {
    local worktree_root go_cache go_mod_cache
    worktree_root="$1"
    go_cache="${worktree_root}/.tart/go-build"
    go_mod_cache="${worktree_root}/.tart/go-mod"

    printf 'export GOCACHE=%q\n' "${go_cache}"
    printf 'export GOMODCACHE=%q\n' "${go_mod_cache}"
}

tart_pack_go_ensure() {
    if command -v go >/dev/null 2>&1; then
        return 0
    fi

    if ! command -v brew >/dev/null 2>&1; then
        echo "go missing and Homebrew is unavailable in the guest" >&2
        return 1
    fi

    retry_command "install Go via Homebrew" brew install go
}

tart_pack_go_verify_toolchain() {
    go version
}
