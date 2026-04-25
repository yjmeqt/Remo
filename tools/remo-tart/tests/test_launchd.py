from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

from remo_tart.launchd import build_submit_argv, label


def test_label_uses_slug() -> None:
    assert label("remo-dev") == "com.remo.tart.remo-dev"


def test_label_slugifies_uppercase() -> None:
    assert label("Remo-Dev") == "com.remo.tart.remo-dev"


def test_build_submit_argv_produces_expected_shape(tmp_path: Path) -> None:
    log = tmp_path / "remo-dev.log"
    argv = build_submit_argv(
        label_str="com.remo.tart.remo-dev",
        tart_args=["run", "remo-dev", "--net-bridged", "en0"],
        log_path=log,
    )
    # ["launchctl", "submit", "-l", label, "--", "/bin/zsh", "-lc", "exec tart run ... > log 2>&1"]
    assert argv[0:4] == ["launchctl", "submit", "-l", "com.remo.tart.remo-dev"]
    assert argv[4] == "--"
    assert argv[5:7] == ["/bin/zsh", "-lc"]
    assert "exec tart run remo-dev --net-bridged en0" in argv[7]
    assert f"> {log}" in argv[7]
    assert "2>&1" in argv[7]


def test_job_present_true_when_launchctl_prints(tmp_path: Path) -> None:
    from remo_tart.launchd import job_present

    with patch("subprocess.run") as run:
        run.return_value.returncode = 0
        assert job_present("com.remo.tart.remo-dev") is True


def test_job_present_false_when_launchctl_fails(tmp_path: Path) -> None:
    from remo_tart.launchd import job_present

    with patch("subprocess.run") as run:
        run.return_value.returncode = 1
        assert job_present("com.remo.tart.remo-dev") is False
