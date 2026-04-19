#!/usr/bin/env bash

tart_pack_rust_worktree_env_exports() {
    local worktree_root cargo_target
    worktree_root="$1"
    cargo_target="${worktree_root}/.tart/cargo-target"

    printf 'export CARGO_TARGET_DIR=%q\n' "${cargo_target}"
}

tart_pack_rust_ensure() {
    local worktree_root
    worktree_root="$1"

    ensure_rustup
    export PATH="${HOME}/.cargo/bin:${PATH}"
    ensure_rust_targets "${worktree_root}"
    ensure_cbindgen
}

tart_pack_rust_verify_toolchain() {
    cargo --version
    cbindgen --version
}
