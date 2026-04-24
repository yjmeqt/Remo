from __future__ import annotations

from click.testing import CliRunner

from remo_tart import __version__
from remo_tart.cli import main


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
