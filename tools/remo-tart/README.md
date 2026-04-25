# remo-tart

CLI for the Remo Tart development VM.

## Install (editable)

```bash
uv tool install --editable tools/remo-tart
remo-tart --help
```

Editable installs point at one on-disk path. If you have multiple Remo
worktrees, pick one as your "CLI dev" worktree and install from there; other
worktrees will use that same installed binary.

## Develop

```bash
cd tools/remo-tart
uv sync --group dev
uv run ruff check .
uv run ruff format .
uv run pytest
```

## Architecture

See [docs/tart-dev-vm.md](../../docs/tart-dev-vm.md) for module-level
architecture and the state machine. See
[docs/tart-development-guide.md](../../docs/tart-development-guide.md) for the
day-to-day workflow.
