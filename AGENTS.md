# AGENTS.md

## Cursor Cloud specific instructions

Remo is a Rust workspace with 5 crates. See `README.md` for architecture overview.

### Toolchain

- Requires Rust ≥ 1.85 (uses `edition2024` dependencies). The VM default may be 1.83; run `rustup default stable` to switch to the latest.
- Package manager: Cargo (standard, no custom build system).

### Key commands

- **Build**: `cargo build`
- **Test**: `cargo test` (26 tests across all crates)
- **Lint**: `cargo clippy` (no custom lint config, standard clippy)
- **Run agent**: `cargo run --example standalone_agent -- <port>`
- **Run host CLI**: `cargo run -p remo-host -- <subcommand>`
  - `demo --addr 127.0.0.1:9876` — scripted walkthrough of all capabilities
  - `call --addr <addr> <capability> '<json>'` — single RPC call
  - `caps --addr <addr>` — list capabilities
  - `repl --addr <addr>` — interactive session

### Running the full system locally

1. Start the agent: `cargo run --example standalone_agent -- 9876`
2. In a second shell, use `remo-host` commands against `127.0.0.1:9876`

The standalone agent uses `MockBridge` (in-memory state) so the full protocol stack works on Linux without iOS/macOS.

### ObjC bridge

`remo-objc` uses `#[cfg(target_os = "ios")]` for real ObjC FFI and provides `MockBridge` on all other platforms. Tests and demos always work on Linux via the mock.

### Non-obvious notes

- The wire protocol uses `rmp_serde::to_vec_named` (map-style MessagePack), not positional arrays. This is required because `Response.error` uses `skip_serializing_if`, which changes element count. Using `to_vec` (positional) will cause deserialization failures.
- The handshake happens on raw `TcpStream` **before** wrapping in `Framed<_, RemoCodec>`. Do not attempt handshake through the codec.
- usbmuxd `Connect` requires the port in **network byte order** (big-endian u16). The helper function `build_connect` handles this automatically.
