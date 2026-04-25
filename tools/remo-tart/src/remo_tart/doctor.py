"""VM health checks. Each check returns a list of Finding instances.

Port of scripts/tart/doctor-dev-vm.sh.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from remo_tart import config, launchd, mount, paths, vm
from remo_tart.errors import RemoTartError


@dataclass(frozen=True)
class Finding:
    level: str  # "ok" | "warning" | "issue"
    message: str
    hint: str | None = None


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------


def _check_config(repo_root: Path) -> tuple[list[Finding], object | None]:
    """Check 1: .tart/project.toml is loadable.

    Returns (findings, project) where project is None on failure.
    """
    try:
        project = config.load(repo_root)
        toml_path = repo_root / ".tart" / "project.toml"
        return [Finding("ok", f"project.toml loaded: {toml_path}")], project
    except RemoTartError as err:
        return [Finding("issue", str(err), hint=err.hint)], None
    except Exception as err:
        return [Finding("issue", f"config load failed: {err}")], None


def _check_vm_exists(vm_name: str) -> tuple[list[Finding], bool]:
    """Check 2: VM exists in the local tart list."""
    try:
        if vm.exists(vm_name):
            return [Finding("ok", f"vm exists: {vm_name}")], True
        return [Finding("issue", f"vm does not exist: {vm_name}")], False
    except Exception as err:
        return [Finding("issue", f"vm.exists check failed: {err}")], False


def _check_vm_running(vm_name: str) -> tuple[list[Finding], bool]:
    """Check 3: VM is running (warning if not — stopped is valid for some workflows)."""
    try:
        if vm.is_running(vm_name):
            return [Finding("ok", f"vm is running: {vm_name}")], True
        return [Finding("warning", f"vm is not running: {vm_name}")], False
    except Exception as err:
        return [Finding("warning", f"vm.is_running check failed: {err}")], False


def _check_launchd(vm_name: str, vm_running: bool, vm_exists: bool) -> list[Finding]:
    """Check 4: Launchd job present; cross-check with running state."""
    findings: list[Finding] = []
    label_str = launchd.label(vm_name)
    try:
        job_present = launchd.job_present(label_str)
    except Exception as err:
        findings.append(Finding("warning", f"launchd check failed: {err}"))
        return findings

    if job_present:
        findings.append(Finding("ok", f"launchd job is loaded: {label_str}"))
    else:
        findings.append(Finding("warning", f"launchd job is not loaded: {label_str}"))

    # Cross-checks
    if not vm_exists and job_present:
        findings.append(Finding("warning", f"stale launchd job for missing vm: {label_str}"))
    if vm_running and not job_present:
        findings.append(Finding("warning", f"vm is running outside launchd management: {vm_name}"))

    return findings


def _check_manifest(vm_name: str) -> tuple[list[Finding], list]:
    """Checks 5 & 6: Manifest exists/non-empty; each host path is a real directory."""
    findings: list[Finding] = []
    manifest_path = paths.mount_manifest_path(vm_name)

    try:
        entries = mount.manifest_read(manifest_path)
    except Exception as err:
        findings.append(Finding("warning", f"manifest read failed: {err}"))
        return findings, []

    if not manifest_path.exists():
        findings.append(Finding("warning", f"mount manifest is missing: {manifest_path}"))
        return findings, []

    if not entries:
        findings.append(Finding("warning", f"mount manifest is empty: {manifest_path}"))
        return findings, []

    findings.append(Finding("ok", f"mount manifest has {len(entries)} entries"))

    for entry in entries:
        try:
            if entry.host_path.is_dir():
                findings.append(
                    Finding("ok", f"mount host path exists: {entry.name} -> {entry.host_path}")
                )
            else:
                findings.append(
                    Finding(
                        "issue",
                        f"mount host path is missing: {entry.name} -> {entry.host_path}",
                    )
                )
        except Exception as err:
            findings.append(Finding("issue", f"mount path check failed for {entry.name}: {err}"))

    return findings, entries


def _check_git_root_bridge(entries: list) -> list[Finding]:
    """Check 7: Git-root bridge entry is recorded in the manifest."""
    for entry in entries:
        if entry.name.endswith("-git-root"):
            return [Finding("ok", f"git-root bridge entry found: {entry.name}")]
    return [Finding("issue", "git-root bridge entry missing from mount manifest")]


def _check_packs(project: object, repo_root: Path) -> list[Finding]:
    """Check 8: Each enabled pack has a corresponding .sh file."""
    findings: list[Finding] = []
    packs_dir = repo_root / ".tart" / "packs"

    for pack_name in project.packs:  # type: ignore[union-attr]
        pack_file = packs_dir / f"{pack_name}.sh"
        try:
            if pack_file.exists():
                findings.append(Finding("ok", f"pack file exists: {pack_name} -> {pack_file}"))
            else:
                findings.append(
                    Finding("issue", f"pack file is missing: {pack_name} -> {pack_file}")
                )
        except Exception as err:
            findings.append(Finding("issue", f"pack file check failed for {pack_name}: {err}"))

    return findings


def _check_ssh_key(vm_name: str) -> list[Finding]:
    """Check 9: SSH key file is present."""
    try:
        key_path = paths.ssh_key_path(vm_name)
        if key_path.is_file():
            return [Finding("ok", f"ssh key exists: {key_path}")]
        return [Finding("warning", f"ssh key is missing: {key_path}")]
    except Exception as err:
        return [Finding("warning", f"ssh key check failed: {err}")]


def _check_ssh_include(vm_name: str) -> list[Finding]:
    """Check 10: User ~/.ssh/config includes the remo-tart managed config."""
    try:
        include_path = paths.ssh_include_path()
        ssh_config = paths.user_ssh_config_path()
        if not ssh_config.is_file():
            return [Finding("warning", f"user ssh config missing: {ssh_config}")]
        content = ssh_config.read_text()
        if str(include_path) in content:
            return [Finding("ok", f"ssh include present in {ssh_config}")]
        return [
            Finding(
                "warning",
                f"ssh include missing from {ssh_config}; expected: Include {include_path}",
            )
        ]
    except Exception as err:
        return [Finding("warning", f"ssh include check failed: {err}")]


# ---------------------------------------------------------------------------
# Aggregate
# ---------------------------------------------------------------------------


def run_all(vm_name: str, repo_root: Path) -> list[Finding]:
    """Run all health checks and return the aggregated list of findings."""
    findings: list[Finding] = []

    # Check 1: config loadable
    config_findings, project = _check_config(repo_root)
    findings.extend(config_findings)

    # Check 2: VM exists
    vm_exists_findings, vm_exists = _check_vm_exists(vm_name)
    findings.extend(vm_exists_findings)

    # Check 3: VM running
    vm_running_findings, vm_running = _check_vm_running(vm_name)
    findings.extend(vm_running_findings)

    # Check 4: launchd job
    findings.extend(_check_launchd(vm_name, vm_running, vm_exists))

    # Check 5 & 6: manifest exists, non-empty, host paths present
    manifest_findings, entries = _check_manifest(vm_name)
    findings.extend(manifest_findings)

    # Check 7: git-root bridge (needs entries from manifest)
    if entries:
        findings.extend(_check_git_root_bridge(entries))
    else:
        findings.append(Finding("issue", "git-root bridge entry missing from mount manifest"))

    # Checks 6-8 need the project config; skip if config load failed
    if project is not None:
        # Check 8: enabled packs have matching files
        findings.extend(_check_packs(project, repo_root))

    # Check 9: SSH key present
    findings.extend(_check_ssh_key(vm_name))

    # Check 10: SSH include present
    findings.extend(_check_ssh_include(vm_name))

    return findings


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def render(findings: list[Finding]) -> str:
    """Return a plain-text multi-line summary of findings."""
    n_ok = sum(1 for f in findings if f.level == "ok")
    n_warn = sum(1 for f in findings if f.level == "warning")
    n_issue = sum(1 for f in findings if f.level == "issue")
    total = len(findings)

    status = "ok" if n_issue == 0 else "issues"

    lines: list[str] = [
        f"status: {status}",
        f"checks: {total}, ok={n_ok}, warnings={n_warn}, issues={n_issue}",
        "",
    ]

    for f in findings:
        lines.append(f"[{f.level}] {f.message}")
        if f.hint:
            lines.append(f"  hint: {f.hint}")

    return "\n".join(lines)


def exit_code(findings: list[Finding]) -> int:
    """Return 1 if any finding has level 'issue', else 0."""
    return 1 if any(f.level == "issue" for f in findings) else 0
