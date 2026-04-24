import pytest

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
