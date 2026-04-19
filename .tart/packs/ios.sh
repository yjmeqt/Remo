#!/usr/bin/env bash

tart_pack_ios_worktree_env_exports() {
    local worktree_root derived_data
    worktree_root="$1"
    derived_data="${worktree_root}/.tart/DerivedData"

    printf 'export REMO_TART_DERIVED_DATA=%q\n' "${derived_data}"
}

tart_pack_ios_ensure() {
    ensure_xcode
}

tart_pack_ios_verify_toolchain() {
    xcodebuild -version
}
