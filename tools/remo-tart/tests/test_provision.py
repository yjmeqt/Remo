from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

from remo_tart.config import ProjectConfig, ScriptsConfig, VmConfig
from remo_tart.mount import MountEntry
from remo_tart.provision import build_guest_script, run_provision


def _cfg(packs: list[str] | None = None) -> ProjectConfig:
    return ProjectConfig(
        slug="remo",
        vm=VmConfig(
            name="remo-dev",
            base_image="img",
            cpu=1,
            memory_gb=1,
            network="shared",
        ),
        packs=packs if packs is not None else ["ios", "rust"],
        scripts=ScriptsConfig(
            provision=".tart/provision.sh",
            verify_worktree=".tart/verify-worktree.sh",
        ),
    )


def _mounts() -> list[MountEntry]:
    return [
        MountEntry("remo-feat", Path("/r")),
        MountEntry("remo-git-root", Path("/r/.git")),
    ]


def test_script_has_shebang_and_strict_mode() -> None:
    script = build_guest_script(_cfg(), _mounts(), packs_dir_guest="/P", verify=True)
    assert script.startswith("#!/usr/bin/env bash")
    assert "set -euo pipefail" in script


def test_script_sources_each_enabled_pack() -> None:
    script = build_guest_script(
        _cfg(["ios", "rust", "node"]), _mounts(), packs_dir_guest="/P", verify=True
    )
    assert 'source "/P/ios.sh"' in script or "source '/P/ios.sh'" in script
    assert 'source "/P/rust.sh"' in script or "source '/P/rust.sh'" in script
    assert 'source "/P/node.sh"' in script or "source '/P/node.sh'" in script


def test_script_calls_ensure_function_for_each_pack() -> None:
    script = build_guest_script(_cfg(["ios", "rust"]), _mounts(), packs_dir_guest="/P", verify=True)
    assert "tart_pack_ios_ensure" in script
    assert "tart_pack_rust_ensure" in script


def test_script_uses_primary_mount_for_project_scripts() -> None:
    script = build_guest_script(_cfg(), _mounts(), packs_dir_guest="/P", verify=True)
    # primary mount is remo-feat (first non-git-root)
    assert "/Volumes/My Shared Files/remo-feat/.tart/provision.sh" in script


def test_script_includes_verify_when_verify_true() -> None:
    script = build_guest_script(_cfg(), _mounts(), packs_dir_guest="/P", verify=True)
    assert "/Volumes/My Shared Files/remo-feat/.tart/verify-worktree.sh" in script


def test_script_omits_verify_when_verify_false() -> None:
    script = build_guest_script(_cfg(), _mounts(), packs_dir_guest="/P", verify=False)
    assert "verify-worktree.sh" not in script


def test_script_skips_git_root_bridge_for_primary_mount_selection() -> None:
    """If mounts only contain git-root bridge, no primary exists — this should fail loudly."""
    import pytest

    from remo_tart.errors import RemoTartError

    with pytest.raises(RemoTartError):
        build_guest_script(
            _cfg(),
            [MountEntry("remo-git-root", Path("/r/.git"))],
            packs_dir_guest="/P",
            verify=True,
        )


def test_script_with_empty_packs_list() -> None:
    script = build_guest_script(_cfg(packs=[]), _mounts(), packs_dir_guest="/P", verify=False)
    # No `source` lines for packs, but the project provision script still runs
    assert "source" not in script
    assert "provision.sh" in script


@patch("remo_tart.provision.vm.exec_interactive")
def test_run_provision_invokes_vm_exec_interactive(exec_i: MagicMock) -> None:
    exec_i.return_value = 0
    result = run_provision("remo-dev", _cfg(), _mounts(), verify=True)
    assert result == 0
    exec_i.assert_called_once()
    (called_vm, called_argv) = exec_i.call_args[0]
    assert called_vm == "remo-dev"
    assert called_argv[0:2] == ["bash", "-c"]
    # The third element is the generated script
    assert "#!/usr/bin/env bash" in called_argv[2]


@patch("remo_tart.provision.vm.exec_interactive")
def test_run_provision_propagates_nonzero(exec_i: MagicMock) -> None:
    exec_i.return_value = 7
    assert run_provision("remo-dev", _cfg(), _mounts(), verify=False) == 7
