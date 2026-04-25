from __future__ import annotations

from pathlib import Path

from remo_tart.mount import (
    MountEntry,
    manifest_prune_stale,
    manifest_read,
    manifest_remove,
    manifest_upsert,
    manifest_write,
    mount_name_for_path,
    parse_mount_spec,
)


def test_manifest_roundtrip(tmp_path: Path) -> None:
    path = tmp_path / "remo-dev.mounts"
    entries = [
        MountEntry("remo", Path("/tmp/remo")),
        MountEntry("remo-git-root", Path("/tmp/remo/.git")),
    ]
    manifest_write(path, entries)
    assert manifest_read(path) == entries


def test_manifest_read_missing_returns_empty(tmp_path: Path) -> None:
    assert manifest_read(tmp_path / "nope.mounts") == []


def test_manifest_read_tolerates_blank_lines(tmp_path: Path) -> None:
    path = tmp_path / "mounts"
    path.write_text("\nremo\t/tmp/remo\n\n")
    assert manifest_read(path) == [MountEntry("remo", Path("/tmp/remo"))]


def test_manifest_upsert_replaces_by_name(tmp_path: Path) -> None:
    path = tmp_path / "mounts"
    manifest_write(path, [MountEntry("remo", Path("/old"))])
    after = manifest_upsert(path, MountEntry("remo", Path("/new")))
    assert after == [MountEntry("remo", Path("/new"))]
    assert manifest_read(path) == after


def test_manifest_upsert_preserves_order_and_appends_new(tmp_path: Path) -> None:
    path = tmp_path / "mounts"
    manifest_write(
        path,
        [
            MountEntry("a", Path("/a")),
            MountEntry("b", Path("/b")),
        ],
    )
    after = manifest_upsert(path, MountEntry("c", Path("/c")))
    assert [e.name for e in after] == ["a", "b", "c"]


def test_manifest_remove(tmp_path: Path) -> None:
    path = tmp_path / "mounts"
    manifest_write(
        path,
        [
            MountEntry("a", Path("/a")),
            MountEntry("b", Path("/b")),
        ],
    )
    after = manifest_remove(path, "a")
    assert [e.name for e in after] == ["b"]


def test_manifest_remove_missing_is_noop(tmp_path: Path) -> None:
    path = tmp_path / "mounts"
    manifest_write(path, [MountEntry("a", Path("/a"))])
    after = manifest_remove(path, "does-not-exist")
    assert [e.name for e in after] == ["a"]


def test_manifest_prune_removes_nonexistent_hosts(tmp_path: Path) -> None:
    live = tmp_path / "live"
    live.mkdir()
    path = tmp_path / "mounts"
    manifest_write(
        path,
        [
            MountEntry("live", live),
            MountEntry("dead", tmp_path / "does-not-exist"),
        ],
    )
    kept, pruned = manifest_prune_stale(path)
    assert pruned == 1
    assert [e.name for e in kept] == ["live"]
    assert manifest_read(path) == kept


def test_mount_name_for_path_equals_slug(tmp_path: Path) -> None:
    p = tmp_path / "remo"
    p.mkdir()
    assert mount_name_for_path("remo", p) == "remo"


def test_mount_name_for_path_prepends_slug(tmp_path: Path) -> None:
    p = tmp_path / "feature-x"
    p.mkdir()
    assert mount_name_for_path("remo", p) == "remo-feature-x"


def test_mount_name_for_path_keeps_prefixed(tmp_path: Path) -> None:
    p = tmp_path / "remo-fix-e2e"
    p.mkdir()
    assert mount_name_for_path("remo", p) == "remo-fix-e2e"


def test_mount_name_for_path_slugifies(tmp_path: Path) -> None:
    p = tmp_path / "Feature_Branch!"
    p.mkdir()
    assert mount_name_for_path("remo", p) == "remo-feature-branch"


def test_parse_mount_spec_host_only(tmp_path: Path) -> None:
    (tmp_path / "proj").mkdir()
    e = parse_mount_spec("remo", str(tmp_path / "proj"))
    assert e.host_path == tmp_path / "proj"
    assert e.name == "remo-proj"


def test_parse_mount_spec_with_explicit_name(tmp_path: Path) -> None:
    (tmp_path / "proj").mkdir()
    e = parse_mount_spec("remo", f"{tmp_path / 'proj'}:custom-name")
    assert e.name == "custom-name"


def test_manifest_prune_does_not_create_missing_file(tmp_path: Path) -> None:
    path = tmp_path / "mounts"
    kept, pruned = manifest_prune_stale(path)
    assert (kept, pruned) == ([], 0)
    assert not path.exists()


def test_manifest_remove_does_not_create_missing_file(tmp_path: Path) -> None:
    path = tmp_path / "mounts"
    after = manifest_remove(path, "anything")
    assert after == []
    assert not path.exists()


def test_manifest_prune_treats_file_as_stale(tmp_path: Path) -> None:
    # A "directory" that's actually a regular file should be pruned (bash -d semantics).
    not_dir = tmp_path / "file"
    not_dir.write_text("x")
    live = tmp_path / "live"
    live.mkdir()
    path = tmp_path / "mounts"
    manifest_write(
        path,
        [
            MountEntry("live", live),
            MountEntry("a-file", not_dir),
        ],
    )
    kept, pruned = manifest_prune_stale(path)
    assert pruned == 1
    assert [e.name for e in kept] == ["live"]
