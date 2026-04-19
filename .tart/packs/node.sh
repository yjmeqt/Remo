#!/usr/bin/env bash

tart_pack_node_worktree_env_exports() {
    local worktree_root npm_cache
    worktree_root="$1"
    npm_cache="${worktree_root}/.tart/npm-cache"

    printf 'export npm_config_cache=%q\n' "${npm_cache}"
}

tart_pack_node_ensure() {
    ensure_node_and_npm
    ensure_codex
}

tart_pack_node_verify_toolchain() {
    npm --version
    codex --version
}
