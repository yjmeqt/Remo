#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "${haystack}" != *"${needle}"* ]]; then
        echo "assertion failed: ${message}" >&2
        echo "missing needle: ${needle}" >&2
        exit 1
    fi
}

create_help="$(bash "${ROOT}/scripts/tart/create-dev-vm.sh" --help)"
assert_contains "${create_help}" "--mount <host-path[:guest-name]>" "create help should document repeatable mounts"
assert_contains "${create_help}" "--recreate" "create help should document recreate"
assert_contains "${create_help}" "--network <mode>" "create help should document network mode selection"

bootstrap_help="$(bash "${ROOT}/scripts/tart/bootstrap-dev-vm.sh" --help)"
assert_contains "${bootstrap_help}" "--recreate" "bootstrap helper should document recreating the shared VM"
assert_contains "${bootstrap_help}" "--no-verify" "bootstrap helper should document optional verification skipping"

use_worktree_help="$(bash "${ROOT}/scripts/tart/use-worktree-dev-vm.sh" --help)"
assert_contains "${use_worktree_help}" "--mount-name <name>" "worktree helper should support overriding the guest mount name"
assert_contains "${use_worktree_help}" "--no-verify" "worktree helper should document optional verification skipping"

connect_help="$(bash "${ROOT}/scripts/tart/connect-dev-vm.sh" --help)"
assert_contains "${connect_help}" "<cli|cursor|vscode>" "connect helper should document the supported connection modes"
assert_contains "${connect_help}" "--new-window" "connect helper should document editor window flags"
assert_contains "${connect_help}" "[<mount-name|host-path>]" "connect helper should explain target selection"

clean_help="$(bash "${ROOT}/scripts/tart/clean-worktree-dev-vm.sh" --help)"
assert_contains "${clean_help}" "--full" "cleanup helper should document full cache removal"
assert_contains "${clean_help}" "[<mount-name|host-path>]" "cleanup helper should explain target selection"

provision_help="$(bash "${ROOT}/scripts/tart/provision-dev-vm.sh" --help)"
assert_contains "${provision_help}" "verify-toolchain" "provision help should document verification subcommands"
assert_contains "${provision_help}" "verify-worktree" "provision help should document worktree verification"

ssh_help="$(bash "${ROOT}/scripts/tart/ssh-dev-vm.sh" --help)"
assert_contains "${ssh_help}" "<mount-name|host-path>" "ssh helper should explain target selection"

codex_help="$(bash "${ROOT}/scripts/tart/codex-dev-vm.sh" --help)"
assert_contains "${codex_help}" "--login" "codex helper should document guest login mode"
assert_contains "${codex_help}" "[-- <codex-args...>]" "codex helper should document argument passthrough"

vscode_help="$(bash "${ROOT}/scripts/tart/open-vscode-dev-vm.sh" --help)"
assert_contains "${vscode_help}" "--print-only" "VS Code launcher should support dry-run output"
assert_contains "${vscode_help}" "[<mount-name|host-path>]" "VS Code launcher should explain target selection"

cursor_help="$(bash "${ROOT}/scripts/tart/open-cursor-dev-vm.sh" --help)"
assert_contains "${cursor_help}" "--print-only" "Cursor launcher should support dry-run output"
assert_contains "${cursor_help}" "[<mount-name|host-path>]" "Cursor launcher should explain target selection"

prepare_ssh_help="$(bash "${ROOT}/scripts/tart/prepare-remote-ssh-dev-vm.sh" --help)"
assert_contains "${prepare_ssh_help}" "--name <vm-name>" "remote ssh helper should support targeting a specific VM"
assert_contains "${prepare_ssh_help}" "Prepare the managed SSH alias" "remote ssh helper should explain the proxy-based setup"

status_help="$(bash "${ROOT}/scripts/tart/status-dev-vm.sh" --help)"
assert_contains "${status_help}" "--name <vm-name>" "status helper should support targeting a specific VM"
assert_contains "${status_help}" "[<mount-name|host-path>]" "status helper should explain optional target selection"

doctor_help="$(bash "${ROOT}/scripts/tart/doctor-dev-vm.sh" --help)"
assert_contains "${doctor_help}" "--name <vm-name>" "doctor helper should support targeting a specific VM"
assert_contains "${doctor_help}" "[<mount-name|host-path>]" "doctor helper should explain optional target selection"

e2e_help="$(bash "${ROOT}/scripts/tart/e2e-dev-vm.sh" --help)"
assert_contains "${e2e_help}" "--name <vm-name>" "e2e helper should support targeting a specific VM"
assert_contains "${e2e_help}" "[<mount-name|host-path>]" "e2e helper should explain optional target selection"
assert_contains "${e2e_help}" "[-- <e2e-args...>]" "e2e helper should document e2e argument passthrough"

destroy_help="$(bash "${ROOT}/scripts/tart/destroy-dev-vm.sh" --help)"
assert_contains "${destroy_help}" "--force" "destroy helper should require explicit deletion"
