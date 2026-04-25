#!/usr/bin/env bash

# Provision Claude Code CLI and XcodeBuildMCP CLI inside the guest.
# Relies on helpers from .tart/packs/_lib.sh:
#   - ensure_node_and_npm
#   - retry_command

_agents_ensure_claude_code() {
    if command -v claude >/dev/null 2>&1; then
        return 0
    fi
    retry_command \
        "install Claude Code CLI" \
        npm install -g @anthropic-ai/claude-code
}

_agents_ensure_xcodebuildmcp() {
    if command -v xcodebuildmcp >/dev/null 2>&1; then
        return 0
    fi
    retry_command \
        "install xcodebuildmcp CLI" \
        npm install -g xcodebuildmcp@latest
}

tart_pack_agents_ensure() {
    ensure_node_and_npm
    _agents_ensure_claude_code
    _agents_ensure_xcodebuildmcp
    echo "Hint: run 'claude' inside the VM to complete first-time login."
}

tart_pack_agents_verify_toolchain() {
    claude --version
    xcodebuildmcp --help | head -n 1
}
