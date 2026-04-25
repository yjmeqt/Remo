from __future__ import annotations

import stat
from pathlib import Path

import pytest

from remo_tart.dispatch import bash_dispatch, find_repo_root
from remo_tart.errors import RemoTartError

pytestmark = pytest.mark.skip(reason="dispatch module deleted in PR 3 (Task 5)")


def _make_fake_repo(tmp_path: Path) -> Path:
    """Create a minimal fake repo with scripts/tart/ and a sample script."""
    scripts = tmp_path / "scripts" / "tart"
    scripts.mkdir(parents=True)
    sample = scripts / "sample.sh"
    sample.write_text("#!/usr/bin/env bash\necho hello $@\n")
    sample.chmod(sample.stat().st_mode | stat.S_IEXEC)
    return tmp_path


def test_find_repo_root_walks_upward(tmp_path: Path) -> None:
    repo = _make_fake_repo(tmp_path)
    nested = repo / "a" / "b" / "c"
    nested.mkdir(parents=True)
    assert find_repo_root(nested) == repo


def test_find_repo_root_raises_when_not_found(tmp_path: Path) -> None:
    # no scripts/tart/ anywhere
    with pytest.raises(RemoTartError) as excinfo:
        find_repo_root(tmp_path)
    assert excinfo.value.hint is not None


def test_bash_dispatch_runs_script(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    repo = _make_fake_repo(tmp_path)
    monkeypatch.chdir(repo)
    result = bash_dispatch("sample.sh", ["world"], capture=True)
    assert result.returncode == 0
    assert result.stdout.strip() == "hello world"


def test_bash_dispatch_propagates_nonzero(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    repo = _make_fake_repo(tmp_path)
    # overwrite sample to fail
    (repo / "scripts" / "tart" / "sample.sh").write_text("#!/usr/bin/env bash\nexit 7\n")
    monkeypatch.chdir(repo)
    result = bash_dispatch("sample.sh", [], capture=True)
    assert result.returncode == 7


def test_bash_dispatch_raises_when_script_missing(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo = _make_fake_repo(tmp_path)
    monkeypatch.chdir(repo)
    with pytest.raises(RemoTartError) as excinfo:
        bash_dispatch("nonexistent.sh", [])
    assert "nonexistent.sh" in str(excinfo.value)
