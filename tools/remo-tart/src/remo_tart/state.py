"""Pure state-machine for the `remo-tart up` command."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto


@dataclass(frozen=True)
class VmState:
    exists: bool
    running: bool
    mount_matches: bool


class Action(Enum):
    CREATE = auto()
    UPDATE_MOUNT_AND_RESTART = auto()
    START = auto()
    ATTACH_MOUNT_AND_START = auto()
    NOTHING = auto()


def decide(state: VmState) -> list[Action]:
    if not state.exists:
        return [Action.CREATE]
    if state.running and state.mount_matches:
        return [Action.NOTHING]
    if state.running and not state.mount_matches:
        return [Action.UPDATE_MOUNT_AND_RESTART]
    if not state.running and state.mount_matches:
        return [Action.START]
    return [Action.ATTACH_MOUNT_AND_START]
