"""SSH config managed-block editor, alias helpers, and keypair management."""

from __future__ import annotations

import contextlib
import os
import re
import subprocess
import tempfile
from pathlib import Path

# ---------------------------------------------------------------------------
# Marker templates
# ---------------------------------------------------------------------------

_BLOCK_BEGIN_TMPL = "# >>> remo tart managed: {vm_name} >>>"
_BLOCK_END_TMPL = "# <<< remo tart managed: {vm_name} <<<"
_INCLUDE_BEGIN = "# >>> remo tart include >>>"
_INCLUDE_END = "# <<< remo tart include <<<"


# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------


def ssh_alias(vm_name: str) -> str:
    """Return the SSH Host alias for *vm_name*: ``tart-<vm-name>``."""
    return f"tart-{vm_name}"


def remote_authority(vm_name: str, guest_user: str, ip: str) -> str:
    """Return the VS Code remote authority string ``ssh-remote+<user>@<ip>``."""
    return f"ssh-remote+{guest_user}@{ip}"


def block_marker_pair(vm_name: str) -> tuple[str, str]:
    """Return ``(begin_marker, end_marker)`` for the managed block of *vm_name*."""
    return (
        _BLOCK_BEGIN_TMPL.format(vm_name=vm_name),
        _BLOCK_END_TMPL.format(vm_name=vm_name),
    )


def include_marker_pair() -> tuple[str, str]:
    """Return ``(begin_marker, end_marker)`` for the include stanza."""
    return _INCLUDE_BEGIN, _INCLUDE_END


def managed_block(vm_name: str, guest_user: str, key_path: Path) -> str:
    """Return the SSH Host block body for *vm_name* (without begin/end markers).

    Pass the result to :func:`upsert_managed_block`, which wraps it with the
    appropriate markers.  The block mirrors ``remo_tart_ssh_config_block`` in
    ``common.sh``.
    """
    alias = ssh_alias(vm_name)
    proxy_cmd = f"tart exec -i {vm_name} /usr/bin/nc 127.0.0.1 22"
    lines = [
        f"Host {alias}",
        "  HostName 127.0.0.1",
        f"  User {guest_user}",
        f"  IdentityFile {key_path}",
        "  IdentitiesOnly yes",
        "  StrictHostKeyChecking no",
        "  UserKnownHostsFile /dev/null",
        "  ServerAliveInterval 30",
        "  ServerAliveCountMax 3",
        f"  ProxyCommand {proxy_cmd}",
        "",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Config file I/O helpers
# ---------------------------------------------------------------------------


def _atomic_write(path: Path, content: str) -> None:
    """Write *content* to *path* atomically, creating parent dirs as needed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent)
    try:
        os.write(fd, content.encode())
        os.close(fd)
        os.replace(tmp, path)
    except Exception:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def _read_text(path: Path) -> str:
    """Return file contents or empty string if file is absent."""
    if not path.exists():
        return ""
    return path.read_text()


def _remove_block(text: str, begin: str, end: str) -> str:
    """Strip the managed block (begin…end inclusive) from *text* using regex."""
    pattern = re.escape(begin) + r".*?" + re.escape(end) + r"\n?"
    return re.sub(pattern, "", text, flags=re.DOTALL)


# ---------------------------------------------------------------------------
# Managed block upsert / remove
# ---------------------------------------------------------------------------


def upsert_managed_block(config_path: Path, vm_name: str, block_text: str) -> None:
    """Insert or replace the managed block for *vm_name* in *config_path*.

    *block_text* is the block body (without markers).  This function wraps it
    with the begin/end marker pair.  If the file already has a block for
    *vm_name*, it is replaced.  Otherwise the wrapped block is appended.
    The write is atomic.
    """
    begin, end = block_marker_pair(vm_name)
    existing = _read_text(config_path)

    base = _remove_block(existing, begin, end) if begin in existing else existing

    # Ensure a newline separator before appending (if content is non-empty).
    if base and not base.endswith("\n"):
        base += "\n"

    wrapped = f"{begin}\n{block_text}{end}\n"
    new_content = base + wrapped

    _atomic_write(config_path, new_content)


def remove_managed_block(config_path: Path, vm_name: str) -> None:
    """Remove the managed block for *vm_name* from *config_path*.

    No-op if the file does not exist or the block is absent.
    """
    if not config_path.exists():
        return

    begin, end = block_marker_pair(vm_name)
    existing = config_path.read_text()

    if begin not in existing:
        return

    new_content = _remove_block(existing, begin, end)
    _atomic_write(config_path, new_content)


# ---------------------------------------------------------------------------
# Include directive helpers
# ---------------------------------------------------------------------------


def ensure_include_in_user_config(user_config: Path, include_path: Path) -> None:
    """Prepend an Include stanza for *include_path* into *user_config*.

    Idempotent: if the Include directive is already present, does nothing.
    """
    include_line = f"Include {include_path}"
    existing = _read_text(user_config)

    if include_line in existing:
        return

    # Build the include block and prepend it.
    block = f"{_INCLUDE_BEGIN}\n{include_line}\n{_INCLUDE_END}\n"
    # Strip any pre-existing include marker block first (in case it refers to a
    # different path — mirrors bash behaviour which removes then re-prepends).
    new_content = _remove_block(existing, _INCLUDE_BEGIN, _INCLUDE_END)
    new_content = block + new_content

    _atomic_write(user_config, new_content)


def remove_include_from_user_config(user_config: Path, include_path: Path) -> None:
    """Remove the Include stanza for *include_path* from *user_config*.

    No-op if the file does not exist or the stanza is absent.
    """
    if not user_config.exists():
        return

    existing = user_config.read_text()
    new_content = _remove_block(existing, _INCLUDE_BEGIN, _INCLUDE_END)
    _atomic_write(user_config, new_content)


# ---------------------------------------------------------------------------
# Keypair management
# ---------------------------------------------------------------------------


def generate_keypair(key_path: Path) -> None:
    """Generate an ed25519 keypair at *key_path* if it does not already exist.

    Idempotent: if both ``key_path`` and ``key_path.pub`` exist and are
    non-empty, returns immediately without regenerating the key.
    """
    pub_path = key_path.with_suffix(key_path.suffix + ".pub")
    if (
        key_path.is_file()
        and pub_path.is_file()
        and key_path.stat().st_size > 0
        and pub_path.stat().st_size > 0
    ):
        return

    key_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "ssh-keygen",
            "-t",
            "ed25519",
            "-N",
            "",
            "-f",
            str(key_path),
            "-C",
            f"remo-tart-{key_path.stem}",
        ],
        check=True,
    )


def public_key(key_path: Path) -> str:
    """Return the contents of ``<key_path>.pub``, stripped of trailing whitespace."""
    pub_path = key_path.with_suffix(key_path.suffix + ".pub")
    return pub_path.read_text().strip()
