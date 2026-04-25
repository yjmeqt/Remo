"""Tests for cli.py — PR 2 (native Python modules, no bash_dispatch)."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from click.testing import CliRunner

from remo_tart import __version__
from remo_tart.cli import main
from remo_tart.state import Action

# ---------------------------------------------------------------------------
# Minimal valid project.toml used by all subcommand tests
# ---------------------------------------------------------------------------

_VALID_TOML = """
[project]
slug = "remo"

[vm]
name = "remo-dev"
base_image = "img"
cpu = 1
memory_gb = 1
network = "shared"

[packs]
enabled = ["ios"]

[scripts]
provision = ".tart/provision.sh"
verify_worktree = ".tart/verify-worktree.sh"
"""


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def fake_repo(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setenv("HOME", str(tmp_path))
    # find_repo_root anchors on .tart/project.toml
    (tmp_path / ".tart").mkdir()
    (tmp_path / ".tart" / "project.toml").write_text(_VALID_TOML)
    monkeypatch.chdir(tmp_path)
    return tmp_path


# ---------------------------------------------------------------------------
# Tests preserved from PR 1 (structure-level)
# ---------------------------------------------------------------------------


def test_help_does_not_crash() -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["--help"])
    assert result.exit_code == 0
    assert "Usage:" in result.output


def test_version_prints_version() -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["--version"])
    assert result.exit_code == 0
    assert __version__ in result.output


def test_all_subcommands_appear_in_help() -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["--help"])
    for cmd in [
        "up",
        "use",
        "start",
        "connect",
        "status",
        "doctor",
        "ssh",
        "destroy",
        "clean-worktree",
        "bootstrap",
    ]:
        assert cmd in result.output, f"{cmd} missing from --help"


def test_run_returns_child_exit_code(monkeypatch: pytest.MonkeyPatch, fake_repo: Path) -> None:
    from remo_tart.cli import _run

    with (
        patch("remo_tart.cli._status.collect") as mock_collect,
        patch("remo_tart.cli._status.render_human") as mock_render,
    ):
        mock_collect.return_value = {}
        mock_render.return_value = "vm: ..."
        monkeypatch.setattr("sys.argv", ["remo-tart", "status"])
        code = _run()
    assert code == 0


# ---------------------------------------------------------------------------
# up subcommand
# ---------------------------------------------------------------------------


def _attach_outcome(
    pool_name: str = "remo-dev",
    actions: tuple = (Action.NOTHING,),
    host: Path | None = None,
) -> object:
    from remo_tart.worktree import AttachOutcome, WorktreeAttachment

    host_path = host if host is not None else Path("/tmp/repo")
    return AttachOutcome(
        actions=actions,
        manifest=(),
        attachment=WorktreeAttachment(
            pool_name=pool_name,
            host_path=host_path,
            guest_path=f"/Volumes/My Shared Files/{pool_name}",
        ),
    )


@patch("remo_tart.cli._connect.connect_vscode")
@patch("remo_tart.cli.worktree.ensure_attached")
def test_up_vscode_invokes_worktree_then_connect(
    ensure: MagicMock,
    connect_vscode: MagicMock,
    fake_repo: Path,
) -> None:
    ensure.return_value = _attach_outcome(actions=(Action.CREATE,), host=fake_repo)
    connect_vscode.return_value = 0
    runner = CliRunner()
    result = runner.invoke(main, ["up", "vscode"])
    assert result.exit_code == 0
    ensure.assert_called_once()
    connect_vscode.assert_called_once()


@patch("remo_tart.cli._connect.connect_cli")
@patch("remo_tart.cli.worktree.ensure_attached")
def test_up_cli_mode_calls_connect_cli(
    ensure: MagicMock,
    connect_cli: MagicMock,
    fake_repo: Path,
) -> None:
    ensure.return_value = _attach_outcome(host=fake_repo)
    connect_cli.return_value = 0
    runner = CliRunner()
    result = runner.invoke(main, ["up"])
    assert result.exit_code == 0
    connect_cli.assert_called_once()


@patch("remo_tart.cli._connect.connect_cursor")
@patch("remo_tart.cli.worktree.ensure_attached")
def test_up_cursor_mode_calls_connect_cursor(
    ensure: MagicMock,
    connect_cursor: MagicMock,
    fake_repo: Path,
) -> None:
    ensure.return_value = _attach_outcome(host=fake_repo)
    connect_cursor.return_value = 0
    runner = CliRunner()
    result = runner.invoke(main, ["up", "cursor"])
    assert result.exit_code == 0
    connect_cursor.assert_called_once()


# ---------------------------------------------------------------------------
# use subcommand
# ---------------------------------------------------------------------------


@patch("remo_tart.cli.worktree.ensure_attached")
def test_use_calls_ensure_attached(ensure: MagicMock, fake_repo: Path) -> None:
    ensure.return_value = _attach_outcome(host=fake_repo)
    runner = CliRunner()
    result = runner.invoke(main, ["use"])
    assert result.exit_code == 0
    ensure.assert_called_once()


@patch("remo_tart.cli.worktree.ensure_attached")
def test_use_with_explicit_path(ensure: MagicMock, fake_repo: Path) -> None:
    ensure.return_value = _attach_outcome(actions=(Action.ATTACH_MOUNT_AND_START,), host=fake_repo)
    runner = CliRunner()
    result = runner.invoke(main, ["use", str(fake_repo)])
    assert result.exit_code == 0
    ensure.assert_called_once()


# ---------------------------------------------------------------------------
# start subcommand
# ---------------------------------------------------------------------------


@patch("remo_tart.cli.launchd.submit")
@patch("remo_tart.cli.launchd.remove")
@patch("remo_tart.cli.vm.build_run_args")
@patch("remo_tart.cli.vm.exists")
def test_start_submits_to_launchd(
    vm_exists: MagicMock,
    build_args: MagicMock,
    launchd_remove: MagicMock,
    launchd_submit: MagicMock,
    fake_repo: Path,
) -> None:
    vm_exists.return_value = True
    build_args.return_value = ["run", "remo-dev"]
    runner = CliRunner()
    result = runner.invoke(main, ["start"])
    assert result.exit_code == 0
    launchd_remove.assert_called_once()
    launchd_submit.assert_called_once()


@patch("remo_tart.cli.vm.exists")
def test_start_raises_when_vm_missing(vm_exists: MagicMock, fake_repo: Path) -> None:
    vm_exists.return_value = False
    runner = CliRunner()
    result = runner.invoke(main, ["start"])
    assert result.exit_code == 1
    assert "vm does not exist" in result.output or result.exit_code == 1


# ---------------------------------------------------------------------------
# connect subcommand
# ---------------------------------------------------------------------------


@patch("remo_tart.cli._connect.connect_vscode")
@patch("remo_tart.cli.vm.is_running")
def test_connect_vscode_when_running(
    is_running: MagicMock,
    connect_vscode: MagicMock,
    fake_repo: Path,
) -> None:
    is_running.return_value = True
    connect_vscode.return_value = 0
    runner = CliRunner()
    result = runner.invoke(main, ["connect", "vscode"])
    assert result.exit_code == 0
    connect_vscode.assert_called_once()


@patch("remo_tart.cli.vm.is_running")
def test_connect_errors_when_not_running(is_running: MagicMock, fake_repo: Path) -> None:
    is_running.return_value = False
    runner = CliRunner()
    result = runner.invoke(main, ["connect", "vscode"])
    assert result.exit_code == 1
    assert "not running" in result.output or result.exit_code == 1


@patch("remo_tart.cli._connect.connect_cli")
@patch("remo_tart.cli.vm.is_running")
def test_connect_cli_default_mode(
    is_running: MagicMock,
    connect_cli: MagicMock,
    fake_repo: Path,
) -> None:
    is_running.return_value = True
    connect_cli.return_value = 0
    runner = CliRunner()
    result = runner.invoke(main, ["connect"])
    assert result.exit_code == 0
    connect_cli.assert_called_once()


# ---------------------------------------------------------------------------
# status subcommand
# ---------------------------------------------------------------------------


@patch("remo_tart.cli._status.collect")
@patch("remo_tart.cli._status.render_human")
def test_status_calls_collect_and_renders(
    render_human: MagicMock,
    collect: MagicMock,
    fake_repo: Path,
) -> None:
    collect.return_value = {"vm": {}}
    render_human.return_value = "vm:\n  name=remo-dev"
    runner = CliRunner()
    result = runner.invoke(main, ["status"])
    assert result.exit_code == 0
    collect.assert_called_once()
    render_human.assert_called_once()


@patch("remo_tart.cli._status.collect")
@patch("remo_tart.cli._status.render_json")
def test_status_json_flag(
    render_json: MagicMock,
    collect: MagicMock,
    fake_repo: Path,
) -> None:
    collect.return_value = {"vm": {}}
    render_json.return_value = '{"vm": {}}'
    runner = CliRunner()
    result = runner.invoke(main, ["status", "--json"])
    assert result.exit_code == 0
    collect.assert_called_once()
    render_json.assert_called_once()


# ---------------------------------------------------------------------------
# doctor subcommand
# ---------------------------------------------------------------------------


@patch("remo_tart.cli._doctor.run_all")
@patch("remo_tart.cli._doctor.render")
@patch("remo_tart.cli._doctor.exit_code")
def test_doctor_runs_all_checks(
    exit_code: MagicMock,
    render: MagicMock,
    run_all: MagicMock,
    fake_repo: Path,
) -> None:
    from remo_tart.doctor import Finding

    findings = [Finding("ok", "all good")]
    run_all.return_value = findings
    render.return_value = "status: ok"
    exit_code.return_value = 0
    runner = CliRunner()
    result = runner.invoke(main, ["doctor"])
    assert result.exit_code == 0
    run_all.assert_called_once()


# ---------------------------------------------------------------------------
# ssh subcommand
# ---------------------------------------------------------------------------


@patch("remo_tart.cli.vm.exec_interactive")
@patch("remo_tart.cli.vm.is_running")
def test_ssh_forwards_args_when_running(
    is_running: MagicMock,
    exec_interactive: MagicMock,
    fake_repo: Path,
) -> None:
    is_running.return_value = True
    exec_interactive.return_value = 0
    runner = CliRunner()
    result = runner.invoke(main, ["ssh", "--", "uname", "-a"])
    assert result.exit_code == 0
    exec_interactive.assert_called_once()
    call_args = exec_interactive.call_args
    assert "uname" in call_args[0][1]
    assert "-a" in call_args[0][1]


@patch("remo_tart.cli.vm.is_running")
def test_ssh_errors_when_not_running(is_running: MagicMock, fake_repo: Path) -> None:
    is_running.return_value = False
    runner = CliRunner()
    result = runner.invoke(main, ["ssh"])
    assert result.exit_code == 1


@patch("remo_tart.cli.vm.exec_interactive")
@patch("remo_tart.cli.vm.is_running", return_value=True)
def test_ssh_with_no_args_defaults_to_interactive_zsh(
    is_running: MagicMock,
    exec_interactive: MagicMock,
    fake_repo: Path,
) -> None:
    exec_interactive.return_value = 0
    runner = CliRunner()
    result = runner.invoke(main, ["ssh"])
    assert result.exit_code == 0
    exec_interactive.assert_called_once()
    (_called_vm, called_argv) = exec_interactive.call_args[0]
    assert called_argv == ["/bin/zsh", "-l"]


# ---------------------------------------------------------------------------
# destroy subcommand
# ---------------------------------------------------------------------------


@patch("remo_tart.cli._ssh.remove_managed_block")
@patch("remo_tart.cli._ssh.remove_include_from_user_config")
@patch("remo_tart.cli.vm.exists")
@patch("remo_tart.cli.vm.delete")
@patch("remo_tart.cli.launchd.remove")
def test_destroy_force_skips_prompt(
    launchd_remove: MagicMock,
    vm_delete: MagicMock,
    vm_exists: MagicMock,
    remove_include: MagicMock,
    remove_block: MagicMock,
    fake_repo: Path,
) -> None:
    vm_exists.return_value = True
    runner = CliRunner()
    result = runner.invoke(main, ["destroy", "--force"])
    assert result.exit_code == 0
    launchd_remove.assert_called_once()
    vm_delete.assert_called_once()
    remove_block.assert_called_once()
    remove_include.assert_called_once()


@patch("remo_tart.cli._ssh.remove_managed_block")
@patch("remo_tart.cli._ssh.remove_include_from_user_config")
@patch("remo_tart.cli.vm.exists")
@patch("remo_tart.cli.vm.delete")
@patch("remo_tart.cli.launchd.remove")
def test_destroy_prompt_abort_exits_nonzero(
    launchd_remove: MagicMock,
    vm_delete: MagicMock,
    vm_exists: MagicMock,
    remove_include: MagicMock,
    remove_block: MagicMock,
    fake_repo: Path,
) -> None:
    vm_exists.return_value = True
    runner = CliRunner()
    result = runner.invoke(main, ["destroy"], input="n\n")
    assert result.exit_code != 0
    vm_delete.assert_not_called()


# ---------------------------------------------------------------------------
# clean-worktree subcommand
# ---------------------------------------------------------------------------


@patch("remo_tart.cli.mount.manifest_remove")
def test_clean_worktree_removes_from_manifest(
    manifest_remove: MagicMock,
    fake_repo: Path,
) -> None:
    manifest_remove.return_value = []
    runner = CliRunner()
    result = runner.invoke(main, ["clean-worktree", str(fake_repo)])
    assert result.exit_code == 0
    manifest_remove.assert_called_once()


@patch("remo_tart.cli.mount.manifest_remove")
def test_clean_worktree_defaults_to_cwd(
    manifest_remove: MagicMock,
    fake_repo: Path,
) -> None:
    manifest_remove.return_value = []
    runner = CliRunner()
    result = runner.invoke(main, ["clean-worktree"])
    assert result.exit_code == 0
    manifest_remove.assert_called_once()


# ---------------------------------------------------------------------------
# bootstrap subcommand
# ---------------------------------------------------------------------------


@patch("remo_tart.cli._connect.connect_cli")
@patch("remo_tart.cli.worktree.ensure_attached")
def test_bootstrap_calls_ensure_attached_and_connect_cli(
    ensure: MagicMock,
    connect_cli: MagicMock,
    fake_repo: Path,
) -> None:
    ensure.return_value = _attach_outcome(actions=(Action.CREATE,), host=fake_repo)
    connect_cli.return_value = 0
    runner = CliRunner()
    result = runner.invoke(main, ["bootstrap"])
    assert result.exit_code == 0
    ensure.assert_called_once()
    connect_cli.assert_called_once()


# ---------------------------------------------------------------------------
# --pool flag coverage
# ---------------------------------------------------------------------------


@patch("remo_tart.cli._connect.connect_cli", return_value=0)
@patch("remo_tart.cli.worktree.ensure_attached")
def test_up_passes_pool_to_ensure_attached(
    ensure: MagicMock,
    connect: MagicMock,
    fake_repo: Path,
) -> None:
    ensure.return_value = _attach_outcome(pool_name="alpha", host=fake_repo)
    runner = CliRunner()
    result = runner.invoke(main, ["up", "--pool", "alpha"], catch_exceptions=False)
    assert result.exit_code == 0
    kwargs = ensure.call_args.kwargs
    assert kwargs.get("pool_name") == "alpha"


@patch("remo_tart.cli._connect.connect_cli", return_value=0)
@patch("remo_tart.cli.worktree.ensure_attached")
def test_up_default_pool_is_none(ensure: MagicMock, connect: MagicMock, fake_repo: Path) -> None:
    ensure.return_value = _attach_outcome(host=fake_repo)
    runner = CliRunner()
    runner.invoke(main, ["up"], catch_exceptions=False)
    kwargs = ensure.call_args.kwargs
    assert kwargs.get("pool_name") is None


@patch("remo_tart.cli.worktree.ensure_attached")
def test_use_accepts_pool(ensure: MagicMock, fake_repo: Path) -> None:
    ensure.return_value = _attach_outcome(pool_name="beta", host=fake_repo)
    runner = CliRunner()
    result = runner.invoke(main, ["use", "--pool", "beta"], catch_exceptions=False)
    assert result.exit_code == 0
    assert ensure.call_args.kwargs.get("pool_name") == "beta"


@patch("remo_tart.cli.launchd.submit")
@patch("remo_tart.cli.launchd.remove")
@patch("remo_tart.cli.vm.exists", return_value=True)
def test_start_uses_pool_name_for_vm(
    exists: MagicMock, remove: MagicMock, submit: MagicMock, fake_repo: Path
) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["start", "--pool", "alpha"], catch_exceptions=False)
    assert result.exit_code == 0
    assert exists.call_args.args == ("alpha",)


@patch("remo_tart.cli.vm.is_running", return_value=True)
@patch("remo_tart.cli._connect.connect_cli", return_value=0)
def test_connect_uses_pool_name(connect: MagicMock, is_running: MagicMock, fake_repo: Path) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["connect", "--pool", "alpha"], catch_exceptions=False)
    assert result.exit_code == 0
    assert connect.call_args.args[0] == "alpha"


@patch("remo_tart.cli._status.collect")
@patch("remo_tart.cli._status.render_human", return_value="ok")
def test_status_uses_pool_name(render: MagicMock, collect: MagicMock, fake_repo: Path) -> None:
    collect.return_value = {}
    runner = CliRunner()
    runner.invoke(main, ["status", "--pool", "alpha"], catch_exceptions=False)
    assert collect.call_args.args[0] == "alpha"


@patch("remo_tart.cli._ssh.remove_include_from_user_config")
@patch("remo_tart.cli._ssh.remove_managed_block")
@patch("remo_tart.cli.vm.exists", return_value=False)
@patch("remo_tart.cli.launchd.remove")
def test_destroy_uses_pool_name(
    ld_remove: MagicMock,
    vm_exists: MagicMock,
    ssh_rm_block: MagicMock,
    ssh_rm_include: MagicMock,
    fake_repo: Path,
) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["destroy", "--pool", "alpha", "--force"], catch_exceptions=False)
    assert result.exit_code == 0
    assert "alpha" in ld_remove.call_args.args[0]


@patch("remo_tart.cli.mount.manifest_remove")
def test_clean_worktree_uses_pool_name(rm: MagicMock, fake_repo: Path) -> None:
    runner = CliRunner()
    result = runner.invoke(
        main, ["clean-worktree", str(fake_repo), "--pool", "alpha"], catch_exceptions=False
    )
    assert result.exit_code == 0
    assert "alpha" in str(rm.call_args.args[0])
