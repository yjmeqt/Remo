#!/usr/bin/env bash

tart_project_slug() {
    printf 'remo\n'
}

tart_project_vm_name() {
    printf 'remo-dev\n'
}

tart_project_base_image() {
    printf 'ghcr.io/cirruslabs/macos-tahoe-xcode:26\n'
}

tart_project_network_mode() {
    printf 'bridged:en0\n'
}

tart_project_cpu_count() {
    printf '6\n'
}

tart_project_memory_gb() {
    printf '12\n'
}

tart_project_packs() {
    cat <<'EOF'
ios
rust
node
EOF
}

tart_project_provision() {
    cat <<'EOF'
make setup
EOF
}

tart_project_verify_worktree() {
    cat <<'EOF'
cargo check --workspace
./build-ios.sh sim
EOF
}
