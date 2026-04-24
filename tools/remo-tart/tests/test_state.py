from __future__ import annotations

from remo_tart.state import Action, VmState, decide


def test_missing_vm_returns_create() -> None:
    assert decide(VmState(exists=False, running=False, mount_matches=False)) == [Action.CREATE]
    # "running" and "mount_matches" are irrelevant when exists=False
    assert decide(VmState(exists=False, running=True, mount_matches=True)) == [Action.CREATE]


def test_stopped_without_mount() -> None:
    assert decide(VmState(exists=True, running=False, mount_matches=False)) == [
        Action.ATTACH_MOUNT_AND_START
    ]


def test_stopped_with_mount() -> None:
    assert decide(VmState(exists=True, running=False, mount_matches=True)) == [Action.START]


def test_running_without_mount() -> None:
    assert decide(VmState(exists=True, running=True, mount_matches=False)) == [
        Action.UPDATE_MOUNT_AND_RESTART
    ]


def test_running_with_mount_is_nothing() -> None:
    assert decide(VmState(exists=True, running=True, mount_matches=True)) == [Action.NOTHING]
