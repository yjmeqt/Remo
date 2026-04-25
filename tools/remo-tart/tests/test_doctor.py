from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from remo_tart.config import ProjectConfig, ScriptsConfig, VmConfig
from remo_tart.doctor import Finding, exit_code, render, run_all


@pytest.fixture
def fake_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setenv("HOME", str(tmp_path))
    return tmp_path


def _cfg() -> ProjectConfig:
    return ProjectConfig(
        slug="remo",
        vm=VmConfig(
            name="remo-dev",
            base_image="img",
            cpu=1,
            memory_gb=1,
            network="shared",
        ),
        packs=["ios", "rust"],
        scripts=ScriptsConfig(
            provision=".tart/provision.sh",
            verify_worktree=".tart/verify-worktree.sh",
        ),
    )


def test_finding_dataclass() -> None:
    f = Finding(level="ok", message="all good")
    assert f.hint is None
    f2 = Finding(level="issue", message="boom", hint="do X")
    assert f2.hint == "do X"


def test_exit_code_returns_1_on_issue() -> None:
    findings = [
        Finding("ok", "good"),
        Finding("warning", "meh"),
        Finding("issue", "broken"),
    ]
    assert exit_code(findings) == 1


def test_exit_code_returns_0_on_no_issues() -> None:
    findings = [Finding("ok", "good"), Finding("warning", "meh")]
    assert exit_code(findings) == 0


def test_render_includes_status_summary() -> None:
    findings = [
        Finding("ok", "vm exists"),
        Finding("warning", "vm not running"),
        Finding("issue", "manifest missing"),
    ]
    text = render(findings)
    assert "status:" in text
    assert "issues" in text  # because we have an issue
    assert "ok=1" in text
    assert "warnings=1" in text
    assert "issues=1" in text


def test_render_includes_hint_when_present() -> None:
    findings = [Finding("issue", "manifest missing", hint="run remo-tart up")]
    text = render(findings)
    assert "hint: run remo-tart up" in text


def test_render_no_issues_says_ok() -> None:
    findings = [Finding("ok", "all checks pass")]
    text = render(findings)
    assert "status: ok" in text


@patch("remo_tart.doctor.config.load")
@patch("remo_tart.doctor.vm.exists", return_value=False)
@patch("remo_tart.doctor.vm.is_running", return_value=False)
@patch("remo_tart.doctor.launchd.job_present", return_value=False)
def test_run_all_with_missing_vm(
    job_present: MagicMock,
    is_running: MagicMock,
    exists: MagicMock,
    load: MagicMock,
    fake_home: Path,
    tmp_path: Path,
) -> None:
    load.return_value = _cfg()
    repo = tmp_path / "repo"
    repo.mkdir()

    findings = run_all("remo-dev", repo)
    levels = [f.level for f in findings]
    assert "issue" in levels  # VM missing
    msgs = " ".join(f.message for f in findings)
    assert "remo-dev" in msgs


@patch("remo_tart.doctor.config.load")
@patch("remo_tart.doctor.vm.exists", return_value=True)
@patch("remo_tart.doctor.vm.is_running", return_value=True)
@patch("remo_tart.doctor.launchd.job_present", return_value=True)
def test_run_all_healthy_vm_no_manifest_yields_warning(
    job_present: MagicMock,
    is_running: MagicMock,
    exists: MagicMock,
    load: MagicMock,
    fake_home: Path,
    tmp_path: Path,
) -> None:
    load.return_value = _cfg()
    repo = tmp_path / "repo"
    repo.mkdir()

    findings = run_all("remo-dev", repo)
    # VM checks pass but no manifest yet → warning
    levels = [f.level for f in findings]
    assert "warning" in levels


def test_run_all_handles_config_load_failure(fake_home: Path, tmp_path: Path) -> None:
    """If project.toml is missing, run_all should still return findings, not crash."""
    repo = tmp_path / "repo"
    repo.mkdir()
    # No .tart/ directory at all → config.load will raise
    findings = run_all("remo-dev", repo)
    levels = [f.level for f in findings]
    # Config-loading failure should produce an issue
    assert "issue" in levels
