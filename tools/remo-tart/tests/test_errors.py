from io import StringIO

import pytest
from rich.console import Console

from remo_tart.console import render_error
from remo_tart.errors import RemoTartError


def test_error_stores_message_and_hint():
    err = RemoTartError("vm is not running", hint="run `remo-tart up` first")
    assert str(err) == "vm is not running"
    assert err.hint == "run `remo-tart up` first"


def test_error_without_hint():
    err = RemoTartError("generic failure")
    assert err.hint is None


def test_error_is_raisable():
    with pytest.raises(RemoTartError) as excinfo:
        raise RemoTartError("boom", hint="do X")
    assert excinfo.value.hint == "do X"


def test_render_error_includes_message_and_hint():
    buf = StringIO()
    console = Console(file=buf, force_terminal=False, width=80)
    err = RemoTartError("vm is not running", hint="run `remo-tart up` first")
    render_error(console, err)
    out = buf.getvalue()
    assert "error: vm is not running" in out
    assert "hint: run `remo-tart up` first" in out


def test_render_error_without_hint_omits_hint_line():
    buf = StringIO()
    console = Console(file=buf, force_terminal=False, width=80)
    render_error(console, RemoTartError("boom"))
    out = buf.getvalue()
    assert "error: boom" in out
    assert "hint:" not in out
