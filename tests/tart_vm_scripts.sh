#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/scripts/tart/common.sh"

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "${expected}" != "${actual}" ]]; then
        echo "assertion failed: ${message}" >&2
        echo "expected: ${expected}" >&2
        echo "actual:   ${actual}" >&2
        exit 1
    fi
}

assert_file_exists() {
    local path="$1"
    local message="$2"

    if [[ ! -e "${path}" ]]; then
        echo "assertion failed: ${message}" >&2
        echo "missing path: ${path}" >&2
        exit 1
    fi
}

assert_file_missing() {
    local path="$1"
    local message="$2"

    if [[ -e "${path}" ]]; then
        echo "assertion failed: ${message}" >&2
        echo "unexpected path: ${path}" >&2
        exit 1
    fi
}

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

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "${haystack}" == *"${needle}"* ]]; then
        echo "assertion failed: ${message}" >&2
        echo "unexpected needle: ${needle}" >&2
        exit 1
    fi
}

assert_eq "${ROOT}" "$(remo_tart_repo_root)" "repo root should resolve from script location"
assert_eq "/Users/yi.jiang/Developer/Remo" "$(remo_tart_project_root)" \
    "project root should resolve through the git common dir"
assert_eq "${ROOT}/.tart/project.sh" "$(remo_tart_project_config_path)" \
    "project config path should live under the repo-local .tart directory"
project_config_override_root="$(mktemp -d)"
REMO_TART_PROJECT_CONFIG_PATH_OVERRIDE="${project_config_override_root}/custom-project.sh"
assert_eq "${project_config_override_root}/custom-project.sh" "$(remo_tart_project_config_path)" \
    "project config path override should win when explicitly provided"
unset REMO_TART_PROJECT_CONFIG_PATH_OVERRIDE
rm -rf "${project_config_override_root}"
packs_csv="$(remo_tart_enabled_packs | paste -sd, -)"
assert_eq "ios,rust,node" "${packs_csv}" \
    "enabled packs should come from the repo-local Tart project manifest"
assert_eq "ghcr.io/cirruslabs/macos-tahoe-xcode:26" "$(remo_tart_project_base_image)" \
    "project base image should resolve from the project manifest"
assert_eq "bridged:en0" "$(remo_tart_project_network_mode)" \
    "project network mode should resolve from the project manifest"
assert_eq "6" "$(remo_tart_project_cpu_count)" \
    "project CPU count should resolve from the project manifest"
assert_eq "12" "$(remo_tart_project_memory_gb)" \
    "project memory should resolve from the project manifest"
assert_eq "/Users/yi.jiang/Developer/Remo/.git" "$(remo_tart_project_git_root)" \
    "project git root should resolve through the shared git directory"
assert_eq "remo-dev" "$(remo_tart_default_vm_name)" "default VM name should be project-oriented"
if error_output="$(remo_tart_validate_pack_name "bad/name" 2>&1)"; then
    echo "assertion failed: invalid Tart pack names should be rejected" >&2
    exit 1
fi
assert_contains "${error_output}" "invalid Tart pack name" \
    "invalid pack-name errors should be explicit"
assert_eq "remo-tart-vm" "$(remo_tart_mount_name_for_path "${ROOT}")" "mount name should come from worktree directory name"
assert_eq "remo-git-root" "$(remo_tart_git_root_mount_name)" \
    "hidden git root mount should be stable"
assert_eq "/Volumes/My Shared Files/remo-tart-vm" \
    "$(remo_tart_guest_mount_path "remo-tart-vm")" \
    "guest mount path should use Tart shared directory root"
assert_eq "remo-tart-vm" "$(remo_tart_resolve_target_mount_name "${ROOT}")" \
    "target mount resolution should derive the mount name from a host path"
assert_eq "remo-tart-vm" "$(remo_tart_resolve_target_mount_name "remo-tart-vm")" \
    "target mount resolution should accept an explicit mount name"
assert_eq "/Volumes/My Shared Files/remo-tart-vm" \
    "$(remo_tart_resolve_target_guest_root "${ROOT}")" \
    "target guest-root resolution should map a host path into the guest mount root"
assert_eq "${ROOT}" \
    "$(remo_tart_resolve_target_host_root "remo-dev" "${ROOT}")" \
    "target host-root resolution should preserve explicit host paths"

parsed_mount="$(remo_tart_parse_mount_spec "${ROOT}")"
assert_eq $'remo-tart-vm\t'"${ROOT}" "${parsed_mount}" \
    "mount-spec parsing should derive the guest mount name when only a host path is provided"
parsed_mount="$(remo_tart_parse_mount_spec "${ROOT}:custom-mount")"
assert_eq $'custom-mount\t'"${ROOT}" "${parsed_mount}" \
    "mount-spec parsing should preserve an explicit guest mount name"

tmp_mount_root="$(mktemp -d)"
if error_output="$(remo_tart_parse_mount_spec "${tmp_mount_root}:" 2>&1)"; then
    echo "assertion failed: empty guest mount names should be rejected" >&2
    exit 1
fi
assert_contains "${error_output}" "guest mount name cannot be empty" \
    "mount-spec parsing should explain empty guest mount names"

if error_output="$(remo_tart_parse_mount_spec "${tmp_mount_root}:bad/name" 2>&1)"; then
    echo "assertion failed: guest mount names with path separators should be rejected" >&2
    exit 1
fi
assert_contains "${error_output}" "invalid guest mount name" \
    "mount-spec parsing should explain invalid guest mount names"

rm -rf "${tmp_mount_root}"
missing_mount_root="${ROOT}/.tart/definitely-missing-dir"
if error_output="$(remo_tart_parse_mount_spec "${missing_mount_root}" 2>&1)"; then
    echo "assertion failed: missing host mount directories should be rejected" >&2
    exit 1
fi
assert_contains "${error_output}" "mount host path must be an existing directory" \
    "mount-spec parsing should require an existing host directory"

assert_eq "ssh-remote+admin@172.28.74.13" \
    "$(remo_tart_remote_authority "172.28.74.13")" \
    "remote authority should combine the guest user and current VM IP"
assert_eq "tart-remo-dev" "$(remo_tart_ssh_alias "remo-dev")" \
    "ssh alias should be stable and avoid colliding with real hostnames"
assert_eq "tart exec -i remo-dev /usr/bin/nc 127.0.0.1 22" \
    "$(remo_tart_ssh_proxy_command "remo-dev")" \
    "ssh proxy command should tunnel through tart exec into the guest loopback sshd"
assert_eq "com.remo.tart.remo-dev" "$(remo_tart_launchd_label "remo-dev")" \
    "launchd label should be stable and project-scoped"
assert_eq "${HOME}/.config/remo/tart/ssh_config" "$(remo_tart_managed_ssh_config_path)" \
    "managed ssh config should live alongside the other host Tart state"

ssh_config_block="$(remo_tart_ssh_config_block "remo-dev")"
assert_contains "${ssh_config_block}" "Host tart-remo-dev" \
    "ssh config block should declare the managed tart alias"
assert_contains "${ssh_config_block}" "ProxyCommand tart exec -i remo-dev /usr/bin/nc 127.0.0.1 22" \
    "ssh config block should route through tart exec instead of the guest bridged IP"
assert_contains "${ssh_config_block}" "IdentityFile ${HOME}/.config/remo/tart/ssh/remo-dev_ed25519" \
    "ssh config block should point at the managed per-VM ssh key"

tmp_file="$(mktemp)"
cat > "${tmp_file}" <<'EOF'
first line
EOF
remo_tart_upsert_managed_block "${tmp_file}" "# >>> begin >>>" "# <<< end <<<" $'managed line 1\nmanaged line 2' append
managed_file_contents="$(cat "${tmp_file}")"
assert_contains "${managed_file_contents}" "# >>> begin >>>" \
    "managed block helper should insert the begin marker"
assert_contains "${managed_file_contents}" "managed line 2" \
    "managed block helper should insert the managed body"

remo_tart_upsert_managed_block "${tmp_file}" "# >>> begin >>>" "# <<< end <<<" "replacement line" append
managed_file_contents="$(cat "${tmp_file}")"
assert_contains "${managed_file_contents}" "replacement line" \
    "managed block helper should replace an existing block body"
assert_not_contains "${managed_file_contents}" "managed line 1" \
    "managed block helper should not duplicate old managed block content"

remo_tart_remove_managed_block "${tmp_file}" "# >>> begin >>>" "# <<< end <<<"
managed_file_contents="$(cat "${tmp_file}")"
assert_eq "first line" "${managed_file_contents}" \
    "managed block removal should restore the unmanaged file content"

cat > "${tmp_file}" <<'EOF'
keep line
Include /tmp/example
keep line 2
EOF
remo_tart_remove_exact_line "${tmp_file}" "Include /tmp/example"
managed_file_contents="$(cat "${tmp_file}")"
assert_not_contains "${managed_file_contents}" "Include /tmp/example" \
    "exact-line removal should delete a legacy include line cleanly"
rm -f "${tmp_file}"

original_home="${HOME}"
tmp_home="$(mktemp -d)"
HOME="${tmp_home}"
mkdir -p "${HOME}/.ssh" "$(remo_tart_ssh_key_dir)"
cat > "$(remo_tart_managed_ssh_config_path)" <<'EOF'
# >>> remo tart managed: remo-dev >>>
Host tart-remo-dev
  HostName 127.0.0.1
# <<< remo tart managed: remo-dev <<<

# >>> remo tart managed: other-dev >>>
Host tart-other-dev
  HostName 127.0.0.1
# <<< remo tart managed: other-dev <<<
EOF
cat > "${HOME}/.ssh/config" <<EOF
# >>> remo tart include >>>
Include $(remo_tart_managed_ssh_config_path)
# <<< remo tart include <<<

Host github.com
  HostName github.com
EOF
touch "$(remo_tart_ssh_key_path "remo-dev")" "$(remo_tart_ssh_key_path "remo-dev").pub"
touch "$(remo_tart_ssh_key_path "other-dev")" "$(remo_tart_ssh_key_path "other-dev").pub"

remo_tart_cleanup_remote_ssh_local_state "remo-dev"
managed_config_contents="$(cat "$(remo_tart_managed_ssh_config_path)")"
ssh_config_contents="$(cat "${HOME}/.ssh/config")"
assert_not_contains "${managed_config_contents}" "Host tart-remo-dev" \
    "cleanup should remove the managed ssh block for the deleted VM"
assert_contains "${managed_config_contents}" "Host tart-other-dev" \
    "cleanup should keep managed ssh blocks for other VMs"
assert_contains "${ssh_config_contents}" "Include $(remo_tart_managed_ssh_config_path)" \
    "cleanup should keep the include when other managed VM blocks remain"
if [[ -e "$(remo_tart_ssh_key_path "remo-dev")" || -e "$(remo_tart_ssh_key_path "remo-dev").pub" ]]; then
    echo "assertion failed: cleanup should remove the deleted VM ssh keypair" >&2
    exit 1
fi

remo_tart_cleanup_remote_ssh_local_state "other-dev"
if [[ -e "$(remo_tart_managed_ssh_config_path)" ]]; then
    echo "assertion failed: cleanup should remove the managed ssh config when no VM blocks remain" >&2
    exit 1
fi
ssh_config_contents="$(cat "${HOME}/.ssh/config")"
assert_not_contains "${ssh_config_contents}" "# >>> remo tart include >>>" \
    "cleanup should remove the managed include block when no VM blocks remain"
assert_contains "${ssh_config_contents}" "Host github.com" \
    "cleanup should preserve the user's unrelated ssh config entries"
HOME="${original_home}"
rm -rf "${tmp_home}"

running_json='{
  "Running" : true,
  "State" : "running"
}'
assert_eq "0" "$(remo_tart_json_is_running "${running_json}"; printf '%s' "$?")" \
    "running-state helper should recognize Tart's capitalized JSON output"

env_exports="$(remo_tart_worktree_env_exports "${ROOT}")"
assert_contains "${env_exports}" "export REMO_TART_WORKTREE_ROOT=" "worktree root export should exist"
assert_contains "${env_exports}" ".tart/cargo-target" "cargo target path should be isolated"
assert_contains "${env_exports}" ".tart/npm-cache" "npm cache path should be isolated"
assert_contains "${env_exports}" ".tart/tmp" "tmp path should be isolated"
assert_contains "${env_exports}" ".tart/DerivedData" "derived data path should be isolated"

shared_network_args="$(remo_tart_network_args "shared")"
assert_eq "" "${shared_network_args}" "shared networking should not add Tart flags"

bridged_network_args="$(remo_tart_network_args "bridged:en0")"
assert_eq "--net-bridged=en0" "${bridged_network_args}" "bridged networking should target a specific interface"

softnet_network_args="$(remo_tart_network_args "softnet")"
assert_eq "--net-softnet" "${softnet_network_args}" "softnet networking should emit the softnet flag"

git_root_mount_entry="$(remo_tart_git_root_mount_entry)"
assert_eq $'remo-git-root\t/Users/yi.jiang/Developer/Remo/.git' "${git_root_mount_entry}" \
    "git root mount entry should map only the host git directory into a hidden guest mount"

bridge_script="$(remo_tart_guest_git_root_bridge_script "/Users/yi.jiang/Developer/Remo/.git" "/Volumes/My Shared Files/remo-git-root")"
assert_contains "${bridge_script}" "if [[ -L \"\${guest_git_parent}\" ]]" \
    "bridge script should handle legacy project-root symlinks from the older broad mount model"
assert_contains "${bridge_script}" "sudo -S rm -f /Users/yi.jiang/Developer/Remo" \
    "bridge script should remove a legacy project-root symlink before creating the parent directory"
assert_contains "${bridge_script}" "sudo -S mkdir -p /Users/yi.jiang/Developer/Remo" \
    "bridge script should create the project-root directory that hosts the bridged .git path"
assert_contains "${bridge_script}" "ln -sfn /Volumes/My\\ Shared\\ Files/remo-git-root /Users/yi.jiang/Developer/Remo/.git" \
    "bridge script should wire only the host-style .git path to the hidden guest mount"

gitignore_contents="$(cat "${ROOT}/.gitignore")"
assert_contains "${gitignore_contents}" ".tart/" \
    ".gitignore should exclude per-worktree Tart state directories"

manifest_tmp="$(mktemp)"
existing_mount_dir="$(mktemp -d)"
missing_mount_dir="${existing_mount_dir}-missing"
cat > "${manifest_tmp}" <<EOF
keep-mount	${existing_mount_dir}
stale-mount	${missing_mount_dir}
EOF
removed_mounts="$(remo_tart_prune_mount_manifest "${manifest_tmp}")"
assert_eq "1" "${removed_mounts}" \
    "manifest pruning should report how many stale mount entries were removed"
manifest_contents="$(cat "${manifest_tmp}")"
assert_contains "${manifest_contents}" "keep-mount" \
    "manifest pruning should keep existing mount entries"
assert_not_contains "${manifest_contents}" "stale-mount" \
    "manifest pruning should drop stale mount entries"

cat > "${manifest_tmp}" <<EOF
keep-mount	${ROOT}
remo-host-root	/Users/yi.jiang/Developer/Remo
EOF
removed_mounts="$(remo_tart_remove_mount_from_manifest "${manifest_tmp}" "remo-host-root")"
assert_eq "1" "${removed_mounts}" \
    "manifest mount removal should report when a named mount entry was removed"
manifest_contents="$(cat "${manifest_tmp}")"
assert_contains "${manifest_contents}" "keep-mount" \
    "manifest mount removal should keep unrelated entries"
assert_not_contains "${manifest_contents}" "remo-host-root" \
    "manifest mount removal should drop the named mount entry"

cat > "${manifest_tmp}" <<EOF
keep-mount	${ROOT}
other-mount	${ROOT}/docs
EOF
original_home="${HOME}"
tmp_home_for_manifest="$(mktemp -d)"
HOME="${tmp_home_for_manifest}"
mkdir -p "$(dirname "$(remo_tart_mount_manifest_path "remo-dev")")"
cp "${manifest_tmp}" "$(remo_tart_mount_manifest_path "remo-dev")"
assert_eq "${ROOT}/docs" "$(remo_tart_mount_host_path_from_manifest "remo-dev" "other-mount")" \
    "manifest mount lookup should resolve the host path for a named mount"
assert_eq "${ROOT}/docs" "$(remo_tart_resolve_target_host_root "remo-dev" "other-mount")" \
    "target host-root resolution should map a mount name through the manifest"
HOME="${original_home}"
rm -rf "${tmp_home_for_manifest}"
rm -rf "${existing_mount_dir}" "${manifest_tmp}"

stub_bin="$(mktemp -d)"
launchctl_log="$(mktemp)"
cat > "${stub_bin}/tart" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    list)
        ;;
    *)
        echo "unexpected tart stub command: $*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "${stub_bin}/tart"

cat > "${stub_bin}/launchctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    print)
        if [[ "${FAKE_LAUNCHD_PRESENT:-0}" == "1" ]]; then
            exit 0
        fi
        exit 1
        ;;
    remove)
        printf '%s\n' "${2:-}" >> "${LAUNCHCTL_LOG}"
        ;;
    *)
        echo "unexpected launchctl stub command: $*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "${stub_bin}/launchctl"

original_path="${PATH}"
removed_launchd_job="$(
    PATH="${stub_bin}:${original_path}" FAKE_LAUNCHD_PRESENT=1 LAUNCHCTL_LOG="${launchctl_log}" \
        bash -c "source \"${ROOT}/scripts/tart/common.sh\"; remo_tart_cleanup_stale_launchd_job \"remo-dev\""
)"
assert_eq "1" "${removed_launchd_job}" \
    "stale launchd cleanup should report when it removed a stale job for a missing VM"
assert_contains "$(cat "${launchctl_log}")" "com.remo.tart.remo-dev" \
    "stale launchd cleanup should remove the VM-scoped launchd label"

: > "${launchctl_log}"
removed_launchd_job="$(
    PATH="${stub_bin}:${original_path}" FAKE_LAUNCHD_PRESENT=0 LAUNCHCTL_LOG="${launchctl_log}" \
        bash -c "source \"${ROOT}/scripts/tart/common.sh\"; remo_tart_cleanup_stale_launchd_job \"remo-dev\""
)"
assert_eq "0" "${removed_launchd_job}" \
    "stale launchd cleanup should report no-op when no stale job is present"
assert_eq "" "$(cat "${launchctl_log}")" \
    "stale launchd cleanup should not remove anything when no stale job exists"
rm -rf "${stub_bin}" "${launchctl_log}"
