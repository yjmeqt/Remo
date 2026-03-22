# Video Streaming Phase 2: Desktop Receiving & Playback — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Receive H.264 StreamFrames on the desktop, distribute to consumers via broadcast channel, and provide a web-based real-time player (axum + WebSocket + MSE) and MP4 file writer. Add a CLI `mirror` command.

**Architecture:** RpcClient's read loop gains StreamFrame handling, distributing frames via `tokio::sync::broadcast`. Two consumers subscribe: (1) an fMP4 muxer that writes .mp4 files, and (2) an axum-based web server that relays frames over WebSocket to a browser MSE player. A JS-side fMP4 remuxer converts Annex-B NALs to fMP4 segments for SourceBuffer. The CLI `mirror` subcommand orchestrates connection, stream start, consumer wiring, and graceful shutdown.

**Tech Stack:** Rust (tokio, axum), H.264 Annex-B/AVCC, fMP4 (fragmented MP4), browser MSE API, JavaScript.

**Spec:** `docs/superpowers/specs/2026-03-22-video-streaming-design.md` — Section 3

---

## File Structure

### New Files

| File | Responsibility |
|---|---|
| `crates/remo-desktop/src/stream_receiver.rs` | `StreamReceiver` type wrapping `broadcast::Receiver<StreamFrame>`, subscription management on `RpcClient` |
| `crates/remo-desktop/src/mp4_muxer.rs` | Annex-B H.264 → fMP4 segment builder (init segment from SPS/PPS, media segments from NAL frames) |
| `crates/remo-desktop/src/web_player/mod.rs` | axum HTTP server: `GET /` serves player HTML, `WS /stream` pushes fMP4 segments |
| `crates/remo-desktop/src/web_player/player.html` | Embedded HTML/JS: MSE-based `<video>` player with JS fMP4 remuxer |

### Modified Files

| File | Change |
|---|---|
| `crates/remo-desktop/src/rpc_client.rs` | Add `broadcast::Sender<StreamFrame>` field, handle `Message::StreamFrame` in read loop, add `start_mirror()`/`stop_mirror()`/`subscribe_stream()` methods |
| `crates/remo-desktop/src/lib.rs` | Export new modules (`stream_receiver`, `mp4_muxer`, `web_player`) |
| `crates/remo-desktop/Cargo.toml` | Add `axum` dep |
| `crates/remo-cli/src/main.rs` | Add `Mirror` subcommand with `--web`, `--save`, `--fps` flags |
| `crates/remo-cli/Cargo.toml` | Add `open` dep (auto-open browser) |
| `Cargo.toml` (workspace) | Add `axum`, `open` to workspace deps |

---

### Task 1: StreamReceiver + RpcClient StreamFrame handling

**Files:**
- Create: `crates/remo-desktop/src/stream_receiver.rs`
- Modify: `crates/remo-desktop/src/rpc_client.rs`
- Modify: `crates/remo-desktop/src/lib.rs`
- Test: `crates/remo-desktop/src/stream_receiver.rs` (unit tests)

- [ ] **Step 1: Write the failing test for StreamReceiver**

Create `stream_receiver.rs` with a test that constructs a `StreamReceiver` from a `broadcast::Receiver<StreamFrame>` and receives a frame:

```rust
// crates/remo-desktop/src/stream_receiver.rs

use remo_protocol::StreamFrame;
use tokio::sync::broadcast;

/// Cloneable receiver for stream frames.
///
/// Wraps a `broadcast::Receiver` so multiple consumers (web player, MP4 muxer)
/// can each get every frame.
pub struct StreamReceiver {
    rx: broadcast::Receiver<StreamFrame>,
}

impl StreamReceiver {
    pub fn new(rx: broadcast::Receiver<StreamFrame>) -> Self {
        Self { rx }
    }

    /// Receive the next frame. Returns `None` when the stream ends
    /// (sender dropped or STREAM_END received).
    pub async fn next_frame(&mut self) -> Option<StreamFrame> {
        loop {
            match self.rx.recv().await {
                Ok(frame) => return Some(frame),
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    tracing::warn!(skipped = n, "stream receiver lagged, frames dropped");
                    continue; // try again, we'll get the next available frame
                }
                Err(broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use remo_protocol::stream_flags;

    #[tokio::test]
    async fn receive_frame() {
        let (tx, rx) = broadcast::channel(16);
        let mut receiver = StreamReceiver::new(rx);

        let frame = StreamFrame {
            stream_id: 1,
            sequence: 0,
            timestamp_us: 1000,
            flags: stream_flags::KEYFRAME,
            data: vec![0, 0, 0, 1, 0x65],
        };
        tx.send(frame.clone()).unwrap();

        let got = receiver.next_frame().await.unwrap();
        assert_eq!(got.stream_id, 1);
        assert_eq!(got.sequence, 0);
        assert_eq!(got.flags, stream_flags::KEYFRAME);
    }

    #[tokio::test]
    async fn closed_returns_none() {
        let (tx, rx) = broadcast::channel::<StreamFrame>(16);
        let mut receiver = StreamReceiver::new(rx);
        drop(tx);
        assert!(receiver.next_frame().await.is_none());
    }
}
```

- [ ] **Step 2: Run test to verify it fails (StreamFrame doesn't impl Clone)**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo test -p remo-desktop stream_receiver`
Expected: Compile error — `StreamFrame` doesn't implement `Clone` (broadcast requires `Clone`)

- [ ] **Step 3: Add Clone derive to StreamFrame in remo-protocol**

In `crates/remo-protocol/src/message.rs`, the `StreamFrame` struct already has `#[derive(Debug, Clone)]` — verify this. If not, add `Clone`. The `broadcast::channel` requires `T: Clone`.

- [ ] **Step 4: Run stream_receiver tests to verify they pass**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo test -p remo-desktop stream_receiver -- --nocapture`
Expected: 2 tests pass

- [ ] **Step 5: Add broadcast channel to RpcClient and handle StreamFrame in read loop**

Modify `rpc_client.rs`:

1. Add a `stream_tx: broadcast::Sender<StreamFrame>` field to `RpcClient`
2. In `from_connection()`, create `broadcast::channel(64)` and clone the sender into the read loop
3. In the read loop, add a match arm before the `Ok(Some(_))` catch-all:

```rust
Ok(Some(Message::StreamFrame(frame))) => {
    // Best-effort broadcast — if no subscribers, frame is dropped
    let _ = stream_tx_r.send(frame);
}
```

4. Add public methods:

```rust
/// Subscribe to stream frames. Each subscriber gets its own copy of every frame.
pub fn subscribe_stream(&self) -> StreamReceiver {
    StreamReceiver::new(self.stream_tx.subscribe())
}

/// Start a mirror stream and return a StreamReceiver for the frames.
pub async fn start_mirror(&self, fps: u32) -> Result<(u32, StreamReceiver), RpcError> {
    let resp = self.call(
        "__start_mirror",
        serde_json::json!({"fps": fps, "codec": "h264"}),
        Duration::from_secs(10),
    ).await?;
    let response = match resp {
        RpcResponse::Json(r) => r,
        RpcResponse::Binary(_) => return Err(RpcError::Closed),
    };
    match response.result {
        remo_protocol::ResponseResult::Ok { data } => {
            let stream_id = data["stream_id"].as_u64().unwrap_or(1) as u32;
            let receiver = self.subscribe_stream();
            Ok((stream_id, receiver))
        }
        remo_protocol::ResponseResult::Error { message, .. } => {
            Err(RpcError::Remote(message))
        }
    }
}

/// Stop a mirror stream.
pub async fn stop_mirror(&self, stream_id: u32) -> Result<(), RpcError> {
    self.call(
        "__stop_mirror",
        serde_json::json!({"stream_id": stream_id}),
        Duration::from_secs(10),
    ).await?;
    Ok(())
}
```

5. Add `Remote(String)` variant to `RpcError`.

- [ ] **Step 5b: Run tests after RpcClient changes**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo test -p remo-desktop`
Expected: All tests pass (including stream_receiver tests from Step 1)

- [ ] **Step 6: Export stream_receiver module from lib.rs**

Add to `crates/remo-desktop/src/lib.rs`:
```rust
pub mod stream_receiver;
pub use stream_receiver::StreamReceiver;
```

- [ ] **Step 7: Run all remo-desktop tests**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo test -p remo-desktop`
Expected: All tests pass

- [ ] **Step 8: Run clippy**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo clippy -p remo-desktop -- -D warnings`
Expected: No warnings

- [ ] **Step 9: Commit**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming
git add crates/remo-desktop/src/stream_receiver.rs crates/remo-desktop/src/rpc_client.rs crates/remo-desktop/src/lib.rs crates/remo-protocol/src/message.rs
git commit -m "feat(desktop): add StreamReceiver and RpcClient stream frame handling"
```

---

### Task 2: fMP4 Muxer (Annex-B → AVCC → fMP4 segments)

**Files:**
- Create: `crates/remo-desktop/src/mp4_muxer.rs`
- Modify: `crates/remo-desktop/src/lib.rs`

The muxer converts a stream of H.264 NAL units (Annex-B format, with 00 00 00 01 start codes) into fMP4 segments suitable for MSE `SourceBuffer.appendBuffer()`.

Two segment types:
- **Init segment** (ftyp + moov): built from SPS/PPS parameter sets, produced once on `CODEC_CONFIG` frame
- **Media segment** (moof + mdat): one per frame/group, NALs converted from Annex-B start codes to AVCC 4-byte length prefixes

- [ ] **Step 1: Write failing tests for NAL parsing and AVCC conversion**

```rust
// crates/remo-desktop/src/mp4_muxer.rs

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn split_annex_b_nals() {
        // Two NAL units with start codes
        let data = vec![
            0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1e, // SPS
            0x00, 0x00, 0x00, 0x01, 0x68, 0xce, 0x38, 0x80, // PPS
        ];
        let nals = split_nals(&data);
        assert_eq!(nals.len(), 2);
        assert_eq!(nals[0], &[0x67, 0x42, 0x00, 0x1e]);
        assert_eq!(nals[1], &[0x68, 0xce, 0x38, 0x80]);
    }

    #[test]
    fn annex_b_to_avcc_conversion() {
        let annex_b = vec![
            0x00, 0x00, 0x00, 0x01, 0x65, 0xAA, 0xBB,
        ];
        let avcc = annex_b_to_avcc(&annex_b);
        // AVCC: 4-byte big-endian length + NAL data
        assert_eq!(avcc, vec![0x00, 0x00, 0x00, 0x03, 0x65, 0xAA, 0xBB]);
    }

    #[test]
    fn init_segment_from_sps_pps() {
        let sps = vec![0x67, 0x42, 0x00, 0x1e, 0xab, 0x40, 0xa0, 0xfd];
        let pps = vec![0x68, 0xce, 0x38, 0x80];
        let muxer = Mp4Muxer::new();
        let init = muxer.build_init_segment(&sps, &pps);
        // Should start with ftyp box
        assert_eq!(&init[4..8], b"ftyp");
        // Should contain moov box
        let moov_pos = init.windows(4).position(|w| w == b"moov");
        assert!(moov_pos.is_some());
    }

    #[test]
    fn media_segment_structure() {
        let sps = vec![0x67, 0x42, 0x00, 0x1e, 0xab, 0x40, 0xa0, 0xfd];
        let pps = vec![0x68, 0xce, 0x38, 0x80];
        let mut muxer = Mp4Muxer::new();
        muxer.set_sps_pps(sps, pps);

        let nal_data = vec![0x00, 0x00, 0x00, 0x01, 0x65, 0xAA, 0xBB];
        let segment = muxer.write_media_segment(&nal_data, 0, true);
        // Should contain moof box
        let moof_pos = segment.windows(4).position(|w| w == b"moof");
        assert!(moof_pos.is_some());
        // Should contain mdat box
        let mdat_pos = segment.windows(4).position(|w| w == b"mdat");
        assert!(mdat_pos.is_some());
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo test -p remo-desktop mp4_muxer`
Expected: Compile error — functions/structs don't exist yet

- [ ] **Step 3: Implement NAL splitting and Annex-B → AVCC conversion**

```rust
/// Split Annex-B byte stream into individual NAL units.
/// Handles both 3-byte (00 00 01) and 4-byte (00 00 00 01) start codes.
fn split_nals(data: &[u8]) -> Vec<&[u8]> {
    // ... find start codes, return slices between them
}

/// Convert Annex-B NALs to AVCC format (4-byte big-endian length prefix per NAL).
fn annex_b_to_avcc(annex_b: &[u8]) -> Vec<u8> {
    let nals = split_nals(annex_b);
    let mut out = Vec::new();
    for nal in nals {
        let len = nal.len() as u32;
        out.extend_from_slice(&len.to_be_bytes());
        out.extend_from_slice(nal);
    }
    out
}
```

- [ ] **Step 4: Run NAL/AVCC tests**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo test -p remo-desktop mp4_muxer::tests::split_annex_b_nals mp4_muxer::tests::annex_b_to_avcc`
Expected: 2 tests pass

- [ ] **Step 5: Implement Mp4Muxer — init segment (ftyp + moov)**

The `Mp4Muxer` struct holds SPS/PPS state and a sequence counter.

`build_init_segment(sps, pps) -> Vec<u8>`:
- Write `ftyp` box: brand=isom, compatible=[isom, iso2, avc1, mp41]
- Write `moov` box containing:
  - `mvhd` (movie header: timescale=90000)
  - `trak` → `tkhd` + `mdia` → `mdhd` + `hdlr`(vide) + `minf` → `vmhd` + `dinf` + `stbl`
  - `stbl` contains: `stsd` with `avc1` sample entry (width/height from SPS) + `avcC` (SPS/PPS in AVCC config record), plus empty `stts`, `stsc`, `stsz`, `stco`
  - `mvex` → `trex` (default sample settings for fragmented MP4)

Key: parse SPS to extract width, height, profile_idc, level_idc for the `avcC` box.

- [ ] **Step 6: Implement Mp4Muxer — media segment (moof + mdat)**

`write_media_segment(nal_data, timestamp_us, is_keyframe) -> Vec<u8>`:
- Convert `nal_data` from Annex-B to AVCC
- Write `moof` box: `mfhd` (sequence_number++) + `traf` → `tfhd`(track_id=1) + `tfdt`(baseMediaDecodeTime from timestamp_us, converted to 90kHz timescale) + `trun`(sample_count=1, data_offset, sample_size, sample_duration, sample_flags for keyframe/non-keyframe)
- Write `mdat` box: AVCC-formatted data
- Patch `trun.data_offset` to point past moof into mdat payload

- [ ] **Step 7: Run all mp4_muxer tests**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo test -p remo-desktop mp4_muxer -- --nocapture`
Expected: All 4 tests pass

- [ ] **Step 8: Add `Mp4Muxer` consumer function**

Add a convenience async function that reads from a `StreamReceiver` and writes fMP4 to a file:

```rust
/// Consume frames from a StreamReceiver and write to an MP4 file.
pub async fn write_mp4_file(
    mut receiver: StreamReceiver,
    path: &std::path::Path,
) -> std::io::Result<()> {
    use std::io::Write;
    let mut file = std::fs::File::create(path)?;
    let mut muxer = Mp4Muxer::new();
    let mut initialized = false;

    while let Some(frame) = receiver.next_frame().await {
        if frame.flags & stream_flags::STREAM_END != 0 {
            break;
        }
        if frame.flags & stream_flags::CODEC_CONFIG != 0 {
            // Parse SPS/PPS from codec config
            let nals = split_nals(&frame.data);
            let (mut sps, mut pps) = (None, None);
            for nal in &nals {
                if !nal.is_empty() {
                    match nal[0] & 0x1F {
                        7 => sps = Some(nal.to_vec()),
                        8 => pps = Some(nal.to_vec()),
                        _ => {}
                    }
                }
            }
            if let (Some(s), Some(p)) = (sps, pps) {
                muxer.set_sps_pps(s.clone(), p.clone());
                if !initialized {
                    let init = muxer.build_init_segment(&s, &p);
                    file.write_all(&init)?;
                    initialized = true;
                }
            }
            continue;
        }
        if !initialized {
            continue; // skip frames before SPS/PPS
        }
        let is_keyframe = frame.flags & stream_flags::KEYFRAME != 0;
        let segment = muxer.write_media_segment(&frame.data, frame.timestamp_us, is_keyframe);
        file.write_all(&segment)?;
    }
    file.flush()?;
    Ok(())
}
```

- [ ] **Step 9: Export mp4_muxer from lib.rs, run clippy**

Add to `crates/remo-desktop/src/lib.rs`:
```rust
pub mod mp4_muxer;
```

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo clippy -p remo-desktop -- -D warnings`
Expected: No warnings

- [ ] **Step 10: Commit**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming
git add crates/remo-desktop/src/mp4_muxer.rs crates/remo-desktop/src/lib.rs
git commit -m "feat(desktop): add fMP4 muxer for H.264 Annex-B to fragmented MP4"
```

---

### Task 3: Web Player Server (axum HTTP + WebSocket)

**Files:**
- Create: `crates/remo-desktop/src/web_player/mod.rs`
- Modify: `crates/remo-desktop/Cargo.toml`
- Modify: `Cargo.toml` (workspace)
- Modify: `crates/remo-desktop/src/lib.rs`

- [ ] **Step 1: Add axum dependencies to workspace and remo-desktop**

In root `Cargo.toml` workspace deps, add:
```toml
axum = { version = "0.8", features = ["ws"] }
```

In `crates/remo-desktop/Cargo.toml` deps, add:
```toml
axum.workspace = true
```

- [ ] **Step 2: Run cargo check to verify deps resolve**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo check -p remo-desktop`
Expected: Compiles successfully

- [ ] **Step 3: Write the web player server module**

Create `crates/remo-desktop/src/web_player/mod.rs`:

```rust
//! Local web server for browser-based mirror playback.
//!
//! - `GET /` serves the embedded HTML/JS player
//! - `WS /stream` pushes raw H.264 NAL frames as binary WebSocket messages
//!   (the browser JS remuxes to fMP4 for MSE)

use std::net::SocketAddr;
use std::sync::Arc;

use axum::{
    Router,
    extract::{State, WebSocketUpgrade, ws::{Message, WebSocket}},
    response::Html,
    routing::get,
};
use remo_protocol::{StreamFrame, stream_flags};
use tokio::sync::broadcast;
use tracing::{debug, info, warn};

/// State shared across axum handlers.
struct PlayerState {
    stream_tx: broadcast::Sender<StreamFrame>,
}

/// Start the web player HTTP server. Returns the bound address.
///
/// Runs until the `shutdown` future completes.
pub async fn start_server(
    stream_tx: broadcast::Sender<StreamFrame>,
    bind_addr: SocketAddr,
    shutdown: impl std::future::Future<Output = ()> + Send + 'static,
) -> std::io::Result<SocketAddr> {
    let state = Arc::new(PlayerState { stream_tx });

    let app = Router::new()
        .route("/", get(serve_player))
        .route("/stream", get(ws_handler))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(bind_addr).await?;
    let addr = listener.local_addr()?;
    info!(%addr, "web player server started");

    tokio::spawn(async move {
        axum::serve(listener, app)
            .with_graceful_shutdown(shutdown)
            .await
            .ok();
    });

    Ok(addr)
}

async fn serve_player() -> Html<&'static str> {
    Html(include_str!("player.html"))
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<PlayerState>>,
) -> impl axum::response::IntoResponse {
    let rx = state.stream_tx.subscribe();
    ws.on_upgrade(move |socket| handle_ws(socket, rx))
}

async fn handle_ws(mut socket: WebSocket, mut rx: broadcast::Receiver<StreamFrame>) {
    debug!("WebSocket client connected");
    loop {
        match rx.recv().await {
            Ok(frame) => {
                if frame.flags & stream_flags::STREAM_END != 0 {
                    break;
                }
                // Send frame as binary: [flags(1B)][timestamp_us(8B)][nal_data...]
                let mut buf = Vec::with_capacity(1 + 8 + frame.data.len());
                buf.push(frame.flags);
                buf.extend_from_slice(&frame.timestamp_us.to_be_bytes());
                buf.extend_from_slice(&frame.data);
                if socket.send(Message::Binary(buf.into())).await.is_err() {
                    break;
                }
            }
            Err(broadcast::error::RecvError::Lagged(n)) => {
                warn!(n, "WebSocket client lagged, skipped frames");
            }
            Err(broadcast::error::RecvError::Closed) => break,
        }
    }
    debug!("WebSocket client disconnected");
}
```

- [ ] **Step 4: Export web_player module from lib.rs**

Add to `crates/remo-desktop/src/lib.rs`:
```rust
pub mod web_player;
```

- [ ] **Step 5: Write a basic test for the web server**

Add a test to `web_player/mod.rs` that verifies the server starts and the player HTML endpoint returns 200:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn server_serves_player_html() {
        let (tx, _) = broadcast::channel::<StreamFrame>(16);
        let bind = SocketAddr::from(([127, 0, 0, 1], 0)); // port 0 = OS picks
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let addr = start_server(tx, bind, async { shutdown_rx.await.ok(); })
            .await
            .unwrap();
        // Fetch the player page
        let resp = reqwest::get(format!("http://{addr}/")).await.unwrap();
        assert_eq!(resp.status(), 200);
        let body = resp.text().await.unwrap();
        assert!(body.contains("<video"));
        drop(shutdown_tx); // stop server
    }
}
```

Note: This requires `reqwest` as a dev-dependency. Add to `crates/remo-desktop/Cargo.toml`:
```toml
[dev-dependencies]
reqwest = { version = "0.12", features = ["rustls-tls"], default-features = false }
```

- [ ] **Step 6: Run cargo check, tests, and clippy**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo test -p remo-desktop web_player && cargo clippy -p remo-desktop -- -D warnings`
Expected: Compiles, test passes, no warnings

- [ ] **Step 7: Commit**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming
git add crates/remo-desktop/src/web_player/ crates/remo-desktop/src/lib.rs crates/remo-desktop/Cargo.toml Cargo.toml
git commit -m "feat(desktop): add axum web player server for mirror streaming"
```

---

### Task 4: Browser Player (HTML/JS with MSE + fMP4 remuxer)

**Files:**
- Create: `crates/remo-desktop/src/web_player/player.html`

This is a single self-contained HTML file with inline JavaScript. The spec lists a separate `fmp4.js` file, but we consolidate it into `player.html` as inline JS to avoid a second `include_bytes!` and simplify the embedded asset pipeline.

It connects to `WS /stream`, receives binary frames, remuxes H.264 NALs into fMP4 segments using a JS fMP4 builder, and feeds them to MSE `SourceBuffer`. JS logic is validated manually via browser; automated JS testing is out of scope for this plan.

- [ ] **Step 1: Create the HTML/JS player file**

Create `crates/remo-desktop/src/web_player/player.html` with:

**HTML structure:**
- `<video autoplay muted>` element (muted for autoplay policy)
- Status overlay showing connection state, FPS, frame count
- Minimal CSS for centered fullscreen video

**JavaScript components:**

1. **WebSocket connection** to `ws://${location.host}/stream`
2. **Frame parser**: Extract `flags(1B) + timestamp_us(8B) + nal_data` from binary messages
3. **NAL parser**: `splitNals(data)` — find Annex-B start codes (00 00 00 01 and 00 00 01), return NAL unit arrays
4. **fMP4 init segment builder** (`buildInitSegment(sps, pps)`):
   - Parse SPS to extract width, height, profile_idc, level_idc
   - Build ftyp box (isom brand)
   - Build moov box with avcC containing SPS/PPS
   - Return Uint8Array
5. **fMP4 media segment builder** (`buildMediaSegment(nalData, timestamp, isKeyframe, seqNum)`):
   - Convert Annex-B NALs to AVCC (4-byte length prefix)
   - Build moof + mdat
   - Return Uint8Array
6. **MSE integration**:
   - `MediaSource` → `SourceBuffer` with codec `video/mp4; codecs="avc1.XXYYZZ"` (derived from SPS bytes)
   - Queue segments, handle `updateend` events
   - Buffer management: remove old data when buffer exceeds 30 seconds

**Flag constants** (matching Rust `stream_flags`):
```javascript
const KEYFRAME = 0x01;
const STREAM_START = 0x02;
const STREAM_END = 0x04;
const CODEC_CONFIG = 0x08;
```

**Flow:**
1. On `CODEC_CONFIG` message: parse SPS/PPS from NALs, build init segment, create MSE SourceBuffer, append init segment
2. On regular frame: build media segment, queue for append
3. On `STREAM_END`: close MediaSource

- [ ] **Step 2: Verify the file is included correctly**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo check -p remo-desktop`
Expected: Compiles (the `include_str!("player.html")` in mod.rs references this file)

- [ ] **Step 3: Commit**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming
git add crates/remo-desktop/src/web_player/player.html
git commit -m "feat(desktop): add browser MSE player with JS fMP4 remuxer"
```

---

### Task 5: CLI Mirror Command

**Files:**
- Modify: `crates/remo-cli/src/main.rs`
- Modify: `crates/remo-cli/Cargo.toml`
- Modify: `Cargo.toml` (workspace)

- [ ] **Step 1: Add `open` dependency**

In root `Cargo.toml` workspace deps:
```toml
open = "5"
```

In `crates/remo-cli/Cargo.toml`:
```toml
open = { workspace = true }
```

- [ ] **Step 2: Add `stream_sender()` method to RpcClient**

The CLI needs access to the broadcast sender for the web player server. Add to `RpcClient` in `crates/remo-desktop/src/rpc_client.rs`:

```rust
/// Get a clone of the stream broadcast sender (for sharing with web server).
pub fn stream_sender(&self) -> broadcast::Sender<StreamFrame> {
    self.stream_tx.clone()
}
```

- [ ] **Step 3: Add Mirror subcommand to CLI**

Add to the `Command` enum in `main.rs`:

```rust
/// Start screen mirroring from a device.
Mirror {
    /// Device address (host:port).
    #[arg(short, long, default_value = "127.0.0.1:9930")]
    addr: SocketAddr,

    /// USB device ID. Overrides --addr.
    #[arg(short, long)]
    device: Option<u32>,

    /// Target FPS.
    #[arg(short, long, default_value = "30")]
    fps: u32,

    /// Open web player in browser.
    #[arg(long)]
    web: bool,

    /// Save mirror stream to MP4 file.
    #[arg(long)]
    save: Option<String>,

    /// Web player bind port.
    #[arg(long, default_value = "8080")]
    port: u16,
},
```

- [ ] **Step 4: Implement cmd_mirror function**

```rust
async fn cmd_mirror(
    addr: SocketAddr,
    device: Option<u32>,
    fps: u32,
    web: bool,
    save: Option<String>,
    port: u16,
) -> Result<()> {
    if !web && save.is_none() {
        anyhow::bail!("specify --web and/or --save for mirror output");
    }

    let (event_tx, _) = mpsc::channel(16);
    let client = connect(device, addr, event_tx).await?;

    let (stream_id, receiver) = client.start_mirror(fps).await
        .map_err(|e| anyhow::anyhow!("failed to start mirror: {e}"))?;

    println!("Mirror started (stream_id={stream_id}, fps={fps})");

    // Start MP4 writer if --save — use the receiver from start_mirror directly
    let mp4_handle = if let Some(ref path) = save {
        // If both --save and --web, use the returned receiver for MP4 and subscribe a new one for web.
        // If only --save, use the returned receiver directly.
        let mp4_receiver = receiver;
        let path = std::path::PathBuf::from(path);
        Some(tokio::spawn(async move {
            if let Err(e) = remo_desktop::mp4_muxer::write_mp4_file(mp4_receiver, &path).await {
                eprintln!("MP4 writer error: {e}");
            }
        }))
    } else {
        // drop the receiver from start_mirror; web player subscribes its own
        drop(receiver);
        None
    };

    // Start web player if --web
    if web {
        let stream_tx = client.stream_sender();
        let bind = SocketAddr::from(([127, 0, 0, 1], port));
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let server_addr = remo_desktop::web_player::start_server(
            stream_tx,
            bind,
            async { shutdown_rx.await.ok(); },
        ).await?;
        let url = format!("http://{server_addr}");
        println!("Web player at {url}");
        let _ = open::that(&url);
    }

    // Wait for Ctrl+C
    println!("Press Ctrl+C to stop...");
    tokio::signal::ctrl_c().await?;

    println!("\nStopping mirror...");
    client.stop_mirror(stream_id).await
        .map_err(|e| anyhow::anyhow!("failed to stop mirror: {e}"))?;

    // Wait for MP4 writer to finish
    if let Some(handle) = mp4_handle {
        handle.await?;
        if let Some(path) = &save {
            println!("Saved to {path}");
        }
    }

    Ok(())
}
```

- [ ] **Step 5: Wire Mirror command in main match**

```rust
Command::Mirror { addr, device, fps, web, save, port } => {
    cmd_mirror(addr, device, fps, web, save, port).await?;
}
```

- [ ] **Step 6: Run cargo check and clippy on the full workspace**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo check && cargo clippy -- -D warnings`
Expected: Compiles, no warnings

- [ ] **Step 7: Commit**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming
git add crates/remo-cli/src/main.rs crates/remo-cli/Cargo.toml crates/remo-desktop/src/rpc_client.rs Cargo.toml
git commit -m "feat(cli): add mirror command with --web and --save options"
```

---

### Task 6: Integration Tests and Final Verification

**Files:**
- Modify: `tests/integration.rs`

- [ ] **Step 1: Add integration test for StreamReceiver with mock frames**

```rust
#[tokio::test]
async fn stream_receiver_broadcast_multiple_subscribers() {
    use remo_protocol::{StreamFrame, stream_flags};
    use tokio::sync::broadcast;

    let (tx, _) = broadcast::channel::<StreamFrame>(16);

    let mut rx1 = remo_desktop::StreamReceiver::new(tx.subscribe());
    let mut rx2 = remo_desktop::StreamReceiver::new(tx.subscribe());

    let frame = StreamFrame {
        stream_id: 1,
        sequence: 0,
        timestamp_us: 0,
        flags: stream_flags::KEYFRAME,
        data: vec![0x65],
    };
    tx.send(frame).unwrap();

    let f1 = rx1.next_frame().await.unwrap();
    let f2 = rx2.next_frame().await.unwrap();
    assert_eq!(f1.sequence, f2.sequence);
}
```

`StreamReceiver::new` is public (set in Task 1, Step 1).

- [ ] **Step 2: Run full test suite**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo test`
Expected: All tests pass (protocol, transport, desktop, integration)

- [ ] **Step 3: Run clippy on entire workspace**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo clippy --workspace -- -D warnings`
Expected: No warnings (except pre-existing remo-bonjour DNS-SD issue)

- [ ] **Step 4: Verify CLI help output**

Run: `cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming && cargo run -p remo-cli -- mirror --help`
Expected: Shows Mirror subcommand with --web, --save, --fps, --port flags

- [ ] **Step 5: Commit**

```bash
cd /Users/yi.jiang/Developer/Remo/.worktrees/video-streaming
git add tests/integration.rs
git commit -m "test: add integration tests for stream receiver broadcast"
```

---

## Dependency Graph

```
Task 1 (StreamReceiver + RpcClient)
  ├── Task 2 (fMP4 Muxer) — needs StreamReceiver for write_mp4_file
  ├── Task 3 (Web Server) — needs broadcast::Sender from RpcClient
  │     └── Task 4 (HTML/JS Player) — file included by Task 3's mod.rs
  └── Task 5 (CLI Mirror) — needs start_mirror, subscribe_stream, stream_sender, mp4_muxer, web_player
        └── depends on Tasks 2, 3, 4
Task 6 (Integration) — depends on all above
```

**Execution order:** Task 1 → Task 4 (player.html, needed by Task 3's `include_str!`) → Task 2 + Task 3 (parallel-safe after Task 4 exists) → Task 5 → Task 6

**Out of scope for Phase 2:** The `remo record` CLI subcommand (Section 3.4 recording commands) is deferred to Phase 3 along with the iOS-side recording infrastructure (ReplayKit, AVAssetWriter, RecordingManager). This plan covers only the mirror stream path end-to-end.
