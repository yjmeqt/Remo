#!/usr/bin/env bash

# Shared helpers for the Tart development VM scripts.
#
# Exported helpers:
# - remo_tart_repo_root
# - remo_tart_project_config_path
# - remo_tart_load_project_config
# - remo_tart_project_root
# - remo_tart_project_git_root
# - remo_tart_validate_pack_name
# - remo_tart_enabled_packs
# - remo_tart_enabled_packs_csv
# - remo_tart_project_pack_path
# - remo_tart_load_project_pack
# - remo_tart_load_enabled_project_packs
# - remo_tart_project_base_image
# - remo_tart_project_network_mode
# - remo_tart_project_cpu_count
# - remo_tart_project_memory_gb
# - remo_tart_default_vm_name
# - remo_tart_mount_name_for_path
# - remo_tart_validate_mount_name
# - remo_tart_resolve_abs_dir
# - remo_tart_parse_mount_spec
# - remo_tart_resolve_target_mount_name
# - remo_tart_resolve_target_guest_root
# - remo_tart_mount_host_path_from_manifest
# - remo_tart_resolve_target_host_root
# - remo_tart_git_root_mount_name
# - remo_tart_git_root_mount_entry
# - remo_tart_guest_mount_path
# - remo_tart_guest_git_root_bridge_script
# - remo_tart_worktree_env_exports
# - remo_tart_network_args
# - remo_tart_require_cmd
# - remo_tart_json_is_running
# - remo_tart_vm_exists
# - remo_tart_vm_is_running
# - remo_tart_vm_ip
# - remo_tart_vm_connect_ip
# - remo_tart_remote_authority
# - remo_tart_remote_alias_authority
# - remo_tart_ssh_alias
# - remo_tart_ssh_proxy_command
# - remo_tart_ssh_key_dir
# - remo_tart_ssh_key_path
# - remo_tart_managed_ssh_config_path
# - remo_tart_ssh_config_block
# - remo_tart_upsert_managed_block
# - remo_tart_remove_managed_block
# - remo_tart_remove_exact_line
# - remo_tart_cleanup_remote_ssh_local_state
# - remo_tart_prepare_remote_ssh
# - remo_tart_host_state_dir
# - remo_tart_load_mount_lines
# - remo_tart_prune_mount_manifest
# - remo_tart_remove_mount_from_manifest
# - remo_tart_mount_manifest_path
# - remo_tart_vm_log_path
# - remo_tart_launchd_label
# - remo_tart_launchd_job_present
# - remo_tart_cleanup_stale_launchd_job
# - remo_tart_launchd_remove
# - remo_tart_launchd_submit_run
# - remo_tart_exec
# - remo_tart_exec_tty
# - remo_tart_exec_script
# - remo_tart_ssh
# - remo_tart_ssh_script
# - remo_tart_require_host_tart

if [[ -n "${REMO_TART_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi
readonly REMO_TART_COMMON_SH_LOADED=1

readonly REMO_TART_DEFAULT_BASE_IMAGE="${TART_BASE_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-xcode:26}"
readonly REMO_TART_SHARED_ROOT="/Volumes/My Shared Files"
readonly REMO_TART_GUEST_USERNAME="${REMO_TART_GUEST_USERNAME:-admin}"
readonly REMO_TART_GUEST_PASSWORD="${REMO_TART_GUEST_PASSWORD:-admin}"
readonly REMO_TART_DEFAULT_CPUS="${REMO_TART_DEFAULT_CPUS:-6}"
readonly REMO_TART_DEFAULT_MEMORY_GB="${REMO_TART_DEFAULT_MEMORY_GB:-12}"
readonly REMO_TART_DEFAULT_NETWORK_MODE="${REMO_TART_DEFAULT_NETWORK_MODE:-shared}"

remo_tart_repo_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "${script_dir}/../.." && pwd
}

remo_tart_project_config_path() {
    if [[ -n "${REMO_TART_PROJECT_CONFIG_PATH_OVERRIDE:-}" ]]; then
        printf '%s\n' "${REMO_TART_PROJECT_CONFIG_PATH_OVERRIDE}"
        return 0
    fi

    printf '%s/.tart/project.sh\n' "$(remo_tart_repo_root)"
}

remo_tart_load_project_config() {
    if [[ -n "${REMO_TART_PROJECT_CONFIG_LOADED:-}" ]]; then
        return 0
    fi

    if [[ -f "$(remo_tart_project_config_path)" ]]; then
        # shellcheck source=/dev/null
        source "$(remo_tart_project_config_path)"
    fi

    readonly REMO_TART_PROJECT_CONFIG_LOADED=1
}

remo_tart_project_root() {
    local repo_root git_common_dir
    repo_root="$(remo_tart_repo_root)"

    if git_common_dir="$(cd "${repo_root}" && git rev-parse --git-common-dir 2>/dev/null)"; then
        case "${git_common_dir}" in
            /*) ;;
            *) git_common_dir="${repo_root}/${git_common_dir}" ;;
        esac
        cd "$(dirname "${git_common_dir}")" && pwd
        return 0
    fi

    printf '%s\n' "${repo_root}"
}

remo_tart_project_git_root() {
    printf '%s/.git\n' "$(remo_tart_project_root)"
}

remo_tart_project_slug() {
    remo_tart_load_project_config

    if declare -F tart_project_slug >/dev/null 2>&1; then
        tart_project_slug
        return 0
    fi

    local repo_root git_common_dir project_name
    repo_root="$(remo_tart_repo_root)"
    if git_common_dir="$(cd "${repo_root}" && git rev-parse --git-common-dir 2>/dev/null)"; then
        project_name="$(basename "$(dirname "${git_common_dir}")")"
    else
        project_name="$(basename "${repo_root}")"
    fi

    remo_tart_slugify "${project_name}"
}

remo_tart_slugify() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cs 'a-z0-9' '-' \
        | sed -E 's/^-+//; s/-+$//; s/-+/-/g'
}

remo_tart_validate_pack_name() {
    local pack_name
    pack_name="$1"

    if [[ ! "${pack_name}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
        echo "invalid Tart pack name: ${pack_name}" >&2
        return 1
    fi
}

remo_tart_enabled_packs() {
    local pack_name
    remo_tart_load_project_config

    if declare -F tart_project_packs >/dev/null 2>&1; then
        while IFS= read -r pack_name; do
            pack_name="${pack_name%%#*}"
            pack_name="${pack_name#"${pack_name%%[![:space:]]*}"}"
            pack_name="${pack_name%"${pack_name##*[![:space:]]}"}"
            [[ -n "${pack_name}" ]] || continue
            printf '%s\n' "${pack_name}"
        done < <(tart_project_packs)
    fi
}

remo_tart_enabled_packs_csv() {
    remo_tart_enabled_packs | paste -sd, -
}

remo_tart_project_pack_path() {
    local pack_name
    pack_name="$1"
    printf '%s/.tart/packs/%s.sh\n' "$(remo_tart_repo_root)" "${pack_name}"
}

remo_tart_load_project_pack() {
    local pack_name pack_var pack_path
    pack_name="$1"

    remo_tart_validate_pack_name "${pack_name}" || return 1

    pack_var="REMO_TART_PACK_LOADED_$(printf '%s' "${pack_name}" | tr -cs 'A-Za-z0-9' '_')"

    if [[ -n "${!pack_var:-}" ]]; then
        return 0
    fi

    pack_path="$(remo_tart_project_pack_path "${pack_name}")"
    if [[ ! -f "${pack_path}" ]]; then
        echo "missing Tart pack file: ${pack_path}" >&2
        return 1
    fi

    # shellcheck source=/dev/null
    source "${pack_path}"
    printf -v "${pack_var}" '1'
}

remo_tart_load_enabled_project_packs() {
    local pack_name

    while IFS= read -r pack_name; do
        [[ -n "${pack_name}" ]] || continue
        remo_tart_load_project_pack "${pack_name}"
    done < <(remo_tart_enabled_packs)
}

remo_tart_project_base_image() {
    remo_tart_load_project_config

    if declare -F tart_project_base_image >/dev/null 2>&1; then
        tart_project_base_image
    else
        printf '%s\n' "${REMO_TART_DEFAULT_BASE_IMAGE}"
    fi
}

remo_tart_project_network_mode() {
    remo_tart_load_project_config

    if declare -F tart_project_network_mode >/dev/null 2>&1; then
        tart_project_network_mode
    else
        printf '%s\n' "${REMO_TART_DEFAULT_NETWORK_MODE}"
    fi
}

remo_tart_project_cpu_count() {
    remo_tart_load_project_config

    if declare -F tart_project_cpu_count >/dev/null 2>&1; then
        tart_project_cpu_count
    else
        printf '%s\n' "${REMO_TART_DEFAULT_CPUS}"
    fi
}

remo_tart_project_memory_gb() {
    remo_tart_load_project_config

    if declare -F tart_project_memory_gb >/dev/null 2>&1; then
        tart_project_memory_gb
    else
        printf '%s\n' "${REMO_TART_DEFAULT_MEMORY_GB}"
    fi
}

remo_tart_default_vm_name() {
    remo_tart_load_project_config

    if declare -F tart_project_vm_name >/dev/null 2>&1; then
        tart_project_vm_name
    else
        printf '%s-dev\n' "$(remo_tart_project_slug)"
    fi
}

remo_tart_git_root_mount_name() {
    printf '%s-git-root\n' "$(remo_tart_project_slug)"
}

remo_tart_git_root_mount_entry() {
    printf '%s\t%s\n' "$(remo_tart_git_root_mount_name)" "$(remo_tart_project_git_root)"
}

remo_tart_mount_name_for_path() {
    local host_path worktree_name project_slug worktree_slug
    host_path="$1"
    worktree_name="$(basename "${host_path}")"
    project_slug="$(remo_tart_project_slug)"
    worktree_slug="$(remo_tart_slugify "${worktree_name}")"

    if [[ "${worktree_slug}" == "${project_slug}" ]]; then
        printf '%s\n' "${project_slug}"
        return 0
    fi

    case "${worktree_slug}" in
        "${project_slug}"-*)
            printf '%s\n' "${worktree_slug}"
            ;;
        *)
            printf '%s-%s\n' "${project_slug}" "${worktree_slug}"
            ;;
    esac
}

remo_tart_validate_mount_name() {
    local mount_name
    mount_name="$1"

    if [[ -z "${mount_name}" ]]; then
        echo "guest mount name cannot be empty" >&2
        return 1
    fi

    if [[ ! "${mount_name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "invalid guest mount name: ${mount_name}" >&2
        return 1
    fi
}

remo_tart_resolve_abs_dir() {
    local input
    input="$1"

    if [[ ! -d "${input}" ]]; then
        echo "mount host path must be an existing directory: ${input}" >&2
        return 1
    fi

    (
        cd "${input}" >/dev/null 2>&1
        pwd
    )
}

remo_tart_parse_mount_spec() {
    local spec host_path guest_name saw_separator
    spec="$1"
    host_path="${spec}"
    guest_name=""
    saw_separator=0

    case "${spec}" in
        *:*)
            host_path="${spec%:*}"
            guest_name="${spec##*:}"
            saw_separator=1
            ;;
    esac

    host_path="$(remo_tart_resolve_abs_dir "${host_path}")" || return 1
    if [[ "${saw_separator}" -eq 0 ]]; then
        guest_name="$(remo_tart_mount_name_for_path "${host_path}")"
    else
        remo_tart_validate_mount_name "${guest_name}" || return 1
    fi

    printf '%s\t%s\n' "${guest_name}" "${host_path}"
}

remo_tart_resolve_target_mount_name() {
    local target_arg
    target_arg="$1"

    if [[ -d "${target_arg}" ]]; then
        remo_tart_mount_name_for_path "${target_arg}"
        return 0
    fi

    printf '%s\n' "${target_arg}"
}

remo_tart_guest_mount_path() {
    local mount_name
    mount_name="$1"
    printf '%s/%s\n' "${REMO_TART_SHARED_ROOT}" "${mount_name}"
}

remo_tart_resolve_target_guest_root() {
    local target_arg
    target_arg="$1"
    remo_tart_guest_mount_path "$(remo_tart_resolve_target_mount_name "${target_arg}")"
}

remo_tart_mount_host_path_from_manifest() {
    local vm_name mount_name manifest_path line line_mount_name
    vm_name="$1"
    mount_name="$2"
    manifest_path="$(remo_tart_mount_manifest_path "${vm_name}")"

    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        line_mount_name="${line%%$'\t'*}"
        if [[ "${line_mount_name}" == "${mount_name}" ]]; then
            printf '%s\n' "${line#*$'\t'}"
            return 0
        fi
    done < <(remo_tart_load_mount_lines "${manifest_path}")

    echo "mount is not recorded for ${vm_name}: ${mount_name}" >&2
    return 1
}

remo_tart_resolve_target_host_root() {
    local vm_name target_arg
    vm_name="$1"
    target_arg="$2"

    if [[ -d "${target_arg}" ]]; then
        remo_tart_resolve_abs_dir "${target_arg}"
        return 0
    fi

    remo_tart_mount_host_path_from_manifest "${vm_name}" "${target_arg}"
}

remo_tart_guest_git_root_bridge_script() {
    local host_git_root guest_mount_root parent_dir
    host_git_root="$1"
    guest_mount_root="$2"
    parent_dir="$(dirname "${host_git_root}")"

    printf 'set -euo pipefail\n'
    printf 'guest_git_root=%q\n' "${host_git_root}"
    printf 'guest_bridge_source=%q\n' "${guest_mount_root}"
    printf 'guest_git_parent=%q\n' "${parent_dir}"
    printf 'if [[ -L "${guest_git_parent}" ]]; then\n'
    printf '    printf "%%s\\n" %q | sudo -S rm -f %q\n' "${REMO_TART_GUEST_PASSWORD}" "${parent_dir}"
    printf 'fi\n'
    printf 'if [[ -e "${guest_git_parent}" && ! -d "${guest_git_parent}" ]]; then\n'
    printf '    echo "guest git parent exists and is not a directory: ${guest_git_parent}" >&2\n'
    printf '    exit 1\n'
    printf 'fi\n'
    printf 'if [[ -L "${guest_git_root}" ]]; then\n'
    printf '    current_target="$(readlink "${guest_git_root}")"\n'
    printf '    if [[ "${current_target}" == "${guest_bridge_source}" ]]; then\n'
    printf '        exit 0\n'
    printf '    fi\n'
    printf 'fi\n'
    printf 'if [[ -e "${guest_git_root}" && ! -L "${guest_git_root}" ]]; then\n'
    printf '    echo "guest git root bridge target already exists and is not a symlink: ${guest_git_root}" >&2\n'
    printf '    exit 1\n'
    printf 'fi\n'
    printf 'printf "%%s\\n" %q | sudo -S mkdir -p %q\n' "${REMO_TART_GUEST_PASSWORD}" "${parent_dir}"
    printf 'printf "%%s\\n" %q | sudo -S ln -sfn %q %q\n' \
        "${REMO_TART_GUEST_PASSWORD}" \
        "${guest_mount_root}" \
        "${host_git_root}"
}

remo_tart_worktree_env_exports() {
    local worktree_root tart_dir derived_data cargo_target npm_cache tmpdir
    worktree_root="$1"
    tart_dir="${worktree_root}/.tart"
    tmpdir="${tart_dir}/tmp"

    remo_tart_load_enabled_project_packs

    printf 'export REMO_TART_WORKTREE_ROOT=%q\n' "${worktree_root}"
    printf 'export TMPDIR=%q\n' "${tmpdir}"

    local pack_name export_func
    while IFS= read -r pack_name; do
        [[ -n "${pack_name}" ]] || continue
        export_func="tart_pack_${pack_name}_worktree_env_exports"
        if declare -F "${export_func}" >/dev/null 2>&1; then
            "${export_func}" "${worktree_root}"
        fi
    done < <(remo_tart_enabled_packs)
}

remo_tart_network_args() {
    local mode interface
    mode="${1:-${REMO_TART_DEFAULT_NETWORK_MODE}}"

    case "${mode}" in
        ""|shared)
            ;;
        softnet)
            printf '%s\n' "--net-softnet"
            ;;
        bridged:*)
            interface="${mode#bridged:}"
            if [[ -z "${interface}" ]]; then
                echo "bridged network mode requires an interface name" >&2
                return 1
            fi
            printf '%s\n' "--net-bridged=${interface}"
            ;;
        *)
            echo "unsupported Tart network mode: ${mode}" >&2
            return 1
            ;;
    esac
}

remo_tart_host_state_dir() {
    printf '%s/.config/remo/tart\n' "${HOME}"
}

remo_tart_load_mount_lines() {
    local manifest_path line
    manifest_path="$1"

    if [[ -f "${manifest_path}" ]]; then
        while IFS= read -r line; do
            [[ -n "${line}" ]] && printf '%s\n' "${line}"
        done < "${manifest_path}"
    fi
}

remo_tart_prune_mount_manifest() {
    local manifest_path line host_path removed_count tmp_path
    manifest_path="$1"
    removed_count=0

    if [[ ! -f "${manifest_path}" ]]; then
        printf '0\n'
        return 0
    fi

    tmp_path="$(mktemp "${TMPDIR:-/tmp}/remo-tart.XXXXXX")"
    : > "${tmp_path}"

    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        host_path="${line#*$'\t'}"
        if [[ -d "${host_path}" ]]; then
            printf '%s\n' "${line}" >> "${tmp_path}"
        else
            removed_count=$((removed_count + 1))
        fi
    done < "${manifest_path}"

    mv "${tmp_path}" "${manifest_path}"
    printf '%s\n' "${removed_count}"
}

remo_tart_remove_mount_from_manifest() {
    local manifest_path mount_name line removed_count tmp_path line_mount_name
    manifest_path="$1"
    mount_name="$2"
    removed_count=0

    if [[ ! -f "${manifest_path}" ]]; then
        printf '0\n'
        return 0
    fi

    tmp_path="$(mktemp "${TMPDIR:-/tmp}/remo-tart.XXXXXX")"
    : > "${tmp_path}"

    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        line_mount_name="${line%%$'\t'*}"
        if [[ "${line_mount_name}" == "${mount_name}" ]]; then
            removed_count=$((removed_count + 1))
        else
            printf '%s\n' "${line}" >> "${tmp_path}"
        fi
    done < "${manifest_path}"

    mv "${tmp_path}" "${manifest_path}"
    printf '%s\n' "${removed_count}"
}

remo_tart_mount_manifest_path() {
    local vm_name
    vm_name="$1"
    printf '%s/%s.mounts\n' "$(remo_tart_host_state_dir)" "${vm_name}"
}

remo_tart_vm_log_path() {
    local vm_name
    vm_name="$1"
    printf '%s/%s.log\n' "$(remo_tart_host_state_dir)" "${vm_name}"
}

remo_tart_launchd_label() {
    local vm_name
    vm_name="$1"
    printf 'com.remo.tart.%s\n' "$(remo_tart_slugify "${vm_name}")"
}

remo_tart_launchd_job_present() {
    local vm_name label
    vm_name="$1"
    label="$(remo_tart_launchd_label "${vm_name}")"
    launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1
}

remo_tart_cleanup_stale_launchd_job() {
    local vm_name
    vm_name="$1"

    if remo_tart_vm_exists "${vm_name}"; then
        printf '0\n'
        return 0
    fi

    if remo_tart_launchd_job_present "${vm_name}"; then
        remo_tart_launchd_remove "${vm_name}"
        printf '1\n'
        return 0
    fi

    printf '0\n'
}

remo_tart_require_cmd() {
    local cmd
    for cmd in "$@"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            echo "required command not found: ${cmd}" >&2
            return 1
        fi
    done
}

remo_tart_require_host_tart() {
    if command -v tart >/dev/null 2>&1; then
        return 0
    fi

    echo "Tart is required on the host. Install it with:" >&2
    echo "  brew install cirruslabs/cli/tart" >&2
    return 1
}

remo_tart_json_is_running() {
    local json
    json="$1"
    printf '%s' "${json}" | grep -Eq '"[Ss]tate"[[:space:]]*:[[:space:]]*"running"'
}

remo_tart_vm_exists() {
    local vm_name
    vm_name="$1"
    tart list --quiet 2>/dev/null | grep -Fxq "${vm_name}"
}

remo_tart_vm_is_running() {
    local vm_name
    vm_name="$1"
    local json
    json="$(tart get "${vm_name}" --format json 2>/dev/null || true)"
    [[ -n "${json}" ]] || return 1
    remo_tart_json_is_running "${json}"
}

remo_tart_vm_ip() {
    local vm_name
    vm_name="$1"
    tart ip "${vm_name}"
}

remo_tart_vm_connect_ip() {
    local vm_name ip
    vm_name="$1"

    if ip="$(tart ip "${vm_name}" 2>/dev/null)"; then
        ip="$(printf '%s' "${ip}" | tr -d '\r')"
        if [[ -n "${ip}" ]]; then
            printf '%s\n' "${ip}"
            return 0
        fi
    fi

    if ! remo_tart_vm_is_running "${vm_name}"; then
        echo "vm is not running: ${vm_name}" >&2
        return 1
    fi

    ip="$(
        tart exec "${vm_name}" /bin/zsh -lc \
            "ipconfig getifaddr en0 2>/dev/null || ifconfig en0 | sed -n 's/^[[:space:]]*inet \\([0-9.]*\\).*/\\1/p' | head -n1" \
            2>/dev/null || true
    )"
    ip="$(printf '%s' "${ip}" | tr -d '\r')"
    if [[ -n "${ip}" ]]; then
        printf '%s\n' "${ip}"
        return 0
    fi

    echo "no reachable VM IP found for ${vm_name}" >&2
    return 1
}

remo_tart_remote_authority() {
    local ip
    ip="$1"
    printf 'ssh-remote+%s@%s\n' "${REMO_TART_GUEST_USERNAME}" "${ip}"
}

remo_tart_remote_alias_authority() {
    local alias
    alias="$1"
    printf 'ssh-remote+%s\n' "${alias}"
}

remo_tart_ssh_alias() {
    local vm_name
    vm_name="$1"
    printf 'tart-%s\n' "$(remo_tart_slugify "${vm_name}")"
}

remo_tart_ssh_proxy_command() {
    local vm_name
    vm_name="$1"
    printf 'tart exec -i %s /usr/bin/nc 127.0.0.1 22\n' "${vm_name}"
}

remo_tart_ssh_key_dir() {
    printf '%s/ssh\n' "$(remo_tart_host_state_dir)"
}

remo_tart_ssh_key_path() {
    local vm_name
    vm_name="$1"
    printf '%s/%s_ed25519\n' "$(remo_tart_ssh_key_dir)" "$(remo_tart_slugify "${vm_name}")"
}

remo_tart_managed_ssh_config_path() {
    printf '%s/ssh_config\n' "$(remo_tart_host_state_dir)"
}

remo_tart_ssh_config_block() {
    local vm_name alias key_path
    vm_name="$1"
    alias="$(remo_tart_ssh_alias "${vm_name}")"
    key_path="$(remo_tart_ssh_key_path "${vm_name}")"

    cat <<EOF
Host ${alias}
  HostName 127.0.0.1
  User ${REMO_TART_GUEST_USERNAME}
  IdentityFile ${key_path}
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ProxyCommand $(remo_tart_ssh_proxy_command "${vm_name}")
EOF
}

remo_tart_upsert_managed_block() {
    local file_path begin_marker end_marker body position tmp_path output_path
    file_path="$1"
    begin_marker="$2"
    end_marker="$3"
    body="$4"
    position="${5:-append}"

    tmp_path="$(mktemp "${TMPDIR:-/tmp}/remo-tart.XXXXXX")"
    output_path="$(mktemp "${TMPDIR:-/tmp}/remo-tart.XXXXXX")"

    if [[ -f "${file_path}" ]]; then
        awk -v begin="${begin_marker}" -v end="${end_marker}" '
            $0 == begin { skipping = 1; next }
            $0 == end { skipping = 0; next }
            !skipping { print }
        ' "${file_path}" > "${tmp_path}"
    else
        : > "${tmp_path}"
    fi

    case "${position}" in
        prepend)
            {
                printf '%s\n' "${begin_marker}"
                printf '%s\n' "${body}"
                printf '%s\n' "${end_marker}"
                if [[ -s "${tmp_path}" ]]; then
                    cat "${tmp_path}"
                fi
            } > "${output_path}"
            ;;
        append)
            {
                if [[ -s "${tmp_path}" ]]; then
                    cat "${tmp_path}"
                fi
                printf '%s\n' "${begin_marker}"
                printf '%s\n' "${body}"
                printf '%s\n' "${end_marker}"
            } > "${output_path}"
            ;;
        *)
            rm -f "${tmp_path}" "${output_path}"
            echo "unsupported managed block position: ${position}" >&2
            return 1
            ;;
    esac

    mv "${output_path}" "${file_path}"
    rm -f "${tmp_path}"
}

remo_tart_remove_managed_block() {
    local file_path begin_marker end_marker tmp_path
    file_path="$1"
    begin_marker="$2"
    end_marker="$3"

    if [[ ! -f "${file_path}" ]]; then
        return 0
    fi

    tmp_path="$(mktemp "${TMPDIR:-/tmp}/remo-tart.XXXXXX")"
    awk -v begin="${begin_marker}" -v end="${end_marker}" '
        $0 == begin { skipping = 1; next }
        $0 == end { skipping = 0; next }
        !skipping { print }
    ' "${file_path}" > "${tmp_path}"
    mv "${tmp_path}" "${file_path}"
}

remo_tart_remove_exact_line() {
    local file_path exact_line tmp_path
    file_path="$1"
    exact_line="$2"

    if [[ ! -f "${file_path}" ]]; then
        return 0
    fi

    tmp_path="$(mktemp "${TMPDIR:-/tmp}/remo-tart.XXXXXX")"
    awk -v exact_line="${exact_line}" '
        $0 == exact_line { next }
        { print }
    ' "${file_path}" > "${tmp_path}"
    mv "${tmp_path}" "${file_path}"
}

remo_tart_cleanup_remote_ssh_local_state() {
    local vm_name managed_config ssh_config key_path begin_marker end_marker include_begin include_end
    vm_name="$1"

    managed_config="$(remo_tart_managed_ssh_config_path)"
    ssh_config="${HOME}/.ssh/config"
    key_path="$(remo_tart_ssh_key_path "${vm_name}")"

    begin_marker="# >>> remo tart managed: ${vm_name} >>>"
    end_marker="# <<< remo tart managed: ${vm_name} <<<"
    include_begin="# >>> remo tart include >>>"
    include_end="# <<< remo tart include <<<"

    rm -f "${key_path}" "${key_path}.pub"

    remo_tart_remove_managed_block "${managed_config}" "${begin_marker}" "${end_marker}"
    if [[ -f "${managed_config}" ]] && ! grep -q '[^[:space:]]' "${managed_config}"; then
        rm -f "${managed_config}"
    fi

    if [[ ! -f "${managed_config}" ]]; then
        remo_tart_remove_managed_block "${ssh_config}" "${include_begin}" "${include_end}"
        remo_tart_remove_exact_line "${ssh_config}" "Include ${managed_config}"
    fi
}

remo_tart_prepare_remote_ssh() {
    local vm_name managed_config ssh_config key_path pubkey begin_marker end_marker
    local include_begin include_end include_line
    vm_name="$1"

    remo_tart_require_cmd tart ssh-keygen

    key_path="$(remo_tart_ssh_key_path "${vm_name}")"
    managed_config="$(remo_tart_managed_ssh_config_path)"
    ssh_config="${HOME}/.ssh/config"

    mkdir -p "$(remo_tart_host_state_dir)" "$(remo_tart_ssh_key_dir)" "${HOME}/.ssh"

    if [[ ! -f "${key_path}" ]]; then
        ssh-keygen -q -t ed25519 -N '' -f "${key_path}" >/dev/null
    fi

    pubkey="$(cat "${key_path}.pub")"
    remo_tart_exec_script "${vm_name}" "
set -euo pipefail
pubkey=$(printf '%q' "${pubkey}")
mkdir -p \"\$HOME/.ssh\"
chmod 700 \"\$HOME/.ssh\"
touch \"\$HOME/.ssh/authorized_keys\"
chmod 600 \"\$HOME/.ssh/authorized_keys\"
grep -Fqx -- \"\$pubkey\" \"\$HOME/.ssh/authorized_keys\" || printf '%s\n' \"\$pubkey\" >> \"\$HOME/.ssh/authorized_keys\"
"

    begin_marker="# >>> remo tart managed: ${vm_name} >>>"
    end_marker="# <<< remo tart managed: ${vm_name} <<<"
    remo_tart_upsert_managed_block \
        "${managed_config}" \
        "${begin_marker}" \
        "${end_marker}" \
        "$(remo_tart_ssh_config_block "${vm_name}")" \
        append

    include_begin="# >>> remo tart include >>>"
    include_end="# <<< remo tart include <<<"
    include_line="Include ${managed_config}"
    remo_tart_remove_exact_line "${ssh_config}" "${include_line}"
    remo_tart_upsert_managed_block \
        "${ssh_config}" \
        "${include_begin}" \
        "${include_end}" \
        "${include_line}" \
        prepend
}

remo_tart_launchd_remove() {
    local vm_name label
    vm_name="$1"
    label="$(remo_tart_launchd_label "${vm_name}")"
    launchctl remove "${label}" >/dev/null 2>&1 || true
}

remo_tart_launchd_submit_run() {
    local vm_name log_path tart_bin cmd shell_command
    vm_name="$1"
    log_path="$2"
    shift 2

    tart_bin="$(command -v tart)"
    cmd="$(printf '%q ' "${tart_bin}" run "$@")"
    shell_command="exec ${cmd}>$(printf '%q' "${log_path}") 2>&1"

    launchctl submit -l "$(remo_tart_launchd_label "${vm_name}")" -- /bin/zsh -lc "${shell_command}"
}

remo_tart_exec() {
    local vm_name
    vm_name="$1"
    shift
    tart exec "${vm_name}" "$@"
}

remo_tart_exec_tty() {
    local vm_name
    vm_name="$1"
    shift
    tart exec -i -t "${vm_name}" "$@"
}

remo_tart_exec_script() {
    local vm_name script_body shell_path
    vm_name="$1"
    script_body="$2"
    shell_path="${3:-/bin/bash}"
    tart exec "${vm_name}" "${shell_path}" -lc "${script_body}"
}

remo_tart_ssh() {
    local vm_name
    vm_name="$1"
    shift

    remo_tart_require_cmd tart ssh
    if ! remo_tart_vm_is_running "${vm_name}"; then
        echo "vm is not running: ${vm_name}" >&2
        return 1
    fi

    remo_tart_prepare_remote_ssh "${vm_name}"
    ssh -o LogLevel=ERROR "$(remo_tart_ssh_alias "${vm_name}")" "$@"
}

remo_tart_ssh_script() {
    local vm_name
    vm_name="$1"
    shift
    remo_tart_ssh "${vm_name}" "$@"
}
