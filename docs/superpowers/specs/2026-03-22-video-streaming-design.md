# Video Streaming & Screen Recording Design

## Goal

Add real-time screen mirroring (15-30 FPS, H.264 hardware-encoded) and screen recording capabilities to Remo, extending the existing binary frame transport protocol. Desktop playback via embedded web player (local HTTP + WebSocket + MSE). Target environments: Simulator (localhost) and USB only.

## Architecture

Extend the existing wire protocol with a new StreamFrame type (0x02) for continuous H.264 frame delivery. iOS captures screen content via CADisplayLink (app-only) or ReplayKit (system-level), encodes with VideoToolbox hardware encoder, and pushes StreamFrame messages over the existing TCP connection. Desktop receives frames through the existing read loop, distributes via broadcast channel to parallel consumers: web player and/or MP4 file writer.

## Decisions

- **Encoding**: H.264 hardware encoding via VideoToolbox (not MJPEG) for bandwidth efficiency
- **Transport**: Extend existing protocol with Type 0x02 StreamFrame (not RTSP/WebRTC) to reuse transport layer
- **Playback**: Web player first (local HTTP + MSE); native macOS window and SDL/FFmpeg are future TODOs
- **Network**: Simulator + USB only; Wi-Fi not in scope
- **Concurrency**: One mirror stream at a time; recording and mirroring can run in parallel
- **Capture roles**: Mirroring always uses CADisplayLink; recording uses ReplayKit or VideoToolbox per user choice

---

## 1. Protocol Layer Extension

### 1.1 New Frame Type: StreamFrame (0x02)

Existing wire format:
```
┌──────────┬──────────┬──────────────┐
│ len (4B) │ type(1B) │   payload    │
│ u32 BE   │          │              │
└──────────┴──────────┴──────────────┘
  0x00 = JSON (Request/Response/Event)
  0x01 = BinaryResponse
  0x02 = StreamFrame  ← NEW
```

StreamFrame payload layout:
```
┌───────────────┬──────────┬──────────────┬───────────┬──────────────────────┐
│ stream_id(4B) │ seq(4B)  │ pts_us(8B)   │ flags(1B) │ data (H.264 NALUs)   │
│ u32 BE        │ u32 BE   │ u64 BE       │           │ remaining bytes      │
└───────────────┴──────────┴──────────────┴───────────┴──────────────────────┘
```

Flag bits:
- bit 0: `KEYFRAME` — this frame is an IDR frame
- bit 1: `STREAM_START` — first frame of the stream
- bit 2: `STREAM_END` — stream terminated
- bit 3: `CODEC_CONFIG` — data contains SPS/PPS only (no picture data)

Flag combinations the encoder produces:
- First message: `CODEC_CONFIG | STREAM_START` — SPS/PPS parameter sets, no picture data
- First picture: `KEYFRAME` — IDR frame
- Regular frames: `0x00` — P-frames
- Periodic IDR: `KEYFRAME` — every 60 frames
- SPS/PPS re-send (on parameter change): `CODEC_CONFIG` alone
- Final message: `STREAM_END`

### 1.2 Rust Type

```rust
pub struct StreamFrame {
    pub stream_id: u32,
    pub sequence: u32,
    pub timestamp_us: u64,  // Microseconds, monotonic from stream start
    pub flags: u8,
    pub data: Vec<u8>,  // H.264 NAL units (Annex-B format)
}
```

New variant in `Message` enum. Like `BinaryResponse`, `StreamFrame` uses binary wire encoding (Type 0x02) and must be annotated `#[serde(skip)]`. The codec encoder must handle `Message::StreamFrame` explicitly before the JSON fallback arm.

```rust
pub enum Message {
    Request(Request),
    Response(Response),
    Event(Event),
    #[serde(skip)]
    BinaryResponse(BinaryResponse),
    #[serde(skip)]
    StreamFrame(StreamFrame),  // NEW
}
```

### 1.3 RPC Control Commands

All control goes through existing Request/Response:

| Capability | Params | Returns |
|---|---|---|
| `__start_mirror` | `{ fps: 30, codec: "h264" }` | `{ stream_id: 1 }` |
| `__stop_mirror` | `{ stream_id: 1 }` | `{ stopped: true }` |
| `__start_recording` | `{ mode: "replaykit" \| "videotoolbox" }` | `{ recording_id: "xxx" }` |
| `__stop_recording` | `{ recording_id: "xxx" }` | `{ size: N, duration: F }` |
| `__download_recording` | `{ recording_id: "xxx" }` | BinaryResponse with .mp4 bytes |

### 1.4 Error Codes

New `ErrorCode` variants for streaming-specific failures:

| Code | Meaning |
|---|---|
| `StreamAlreadyActive` | A mirror stream is already running (single-stream constraint) |
| `AuthorizationDenied` | ReplayKit user authorization was denied |
| `RecordingNotFound` | Invalid recording_id in stop/download |

### 1.5 MAX_FRAME_SIZE

Increase from 16 MiB to 64 MiB. Recordings exceeding 64 MiB return an error from `__download_recording` with message indicating the file is too large. Chunked transfer for very large recordings is a future optimization.

---

## 2. iOS Capture & Encoding

### 2.1 Screen Capture Sources

**CADisplayLink (self-capture, used for mirroring):**
- Reuses `drawViewHierarchyInRect:afterScreenUpdates:` from existing screenshot path
- CADisplayLink callback on main thread at target FPS
- Produces `CVPixelBuffer` from rendered view hierarchy
- Only captures the app's own content (no status bar, no system UI)
- No authorization required

**ReplayKit (system-level capture, used for recording):**
- `RPScreenRecorder.shared().startCapture { sampleBuffer, type, error in ... }`
- Callback provides `CMSampleBuffer` directly usable by VideoToolbox or AVAssetWriter
- Captures entire screen including system UI overlays
- First use triggers system authorization dialog

**Capture source constraints:**
- Mirroring always uses CADisplayLink (app-only, no auth required)
- Recording mode "replaykit" uses RPScreenRecorder → AVAssetWriter (system-level)
- Recording mode "videotoolbox" uses CADisplayLink → VTCompressionSession → AVAssetWriter (app-only)
- Mirroring + ReplayKit recording can run in parallel (independent pipelines)
- Mirroring + VideoToolbox recording share the CADisplayLink source; each captured frame is sent to both the network encoder and the local file writer

### 2.2 H.264 Hardware Encoder

VideoToolbox `VTCompressionSession` configuration:
- Profile: H.264 Main Profile (broad compatibility)
- Bitrate: 2-5 Mbps (adjustable via params)
- Keyframe interval: 60 frames (2 seconds at 30 FPS)
- Real-time encoding: `kVTCompressionPropertyKey_RealTime = true`
- Pixel format: `kCVPixelFormatType_32BGRA`

Encoding pipeline:
```
CVPixelBuffer ──► VTCompressionSessionEncodeFrame()
                        │ (async callback on encode thread)
                        ▼
                  CMSampleBuffer (encoded)
                        │
                        ├─ Extract SPS/PPS from CMFormatDescription (on IDR frames)
                        ├─ Extract NAL units from CMBlockBuffer
                        ├─ Convert length-prefixed NALs to Annex-B format (start codes)
                        └─ Wrap in StreamFrame → send via Connection
```

### 2.3 ObjC Bridge (remo-objc)

New modules:
- `screen_capture.rs` — CADisplayLink loop management, CVPixelBuffer production
- `video_encoder.rs` — VTCompressionSession create/encode/flush/teardown
- `replay_kit.rs` — RPScreenRecorder start/stop capture wrapper
- `recording.rs` — AVAssetWriter for local .mp4 file recording

All VideoToolbox calls are C API, called directly via Rust FFI (`extern "C"`).
CADisplayLink and ReplayKit use `objc2` crate `msg_send!` macro.

### 2.4 Threading Model

```
Main Thread ──── CADisplayLink callback / ReplayKit callback
                    │ (CVPixelBuffer / CMSampleBuffer)
                    ▼
VT Encode Thread ── VTCompressionSession async encoding
                    │ (encoded NAL units)
                    ▼
Tokio Thread ────── StreamFrame packaging → conn.send()
```

Cross-thread communication: VTCompressionSession's output callback fires on an internal VideoToolbox thread (not a tokio thread). The callback must use `mpsc::Sender::try_send()` (non-async) to pass encoded frames to the tokio sender task. Using async `.send().await` inside a synchronous C callback would panic due to missing tokio runtime context.

The bounded `try_send` channel provides natural backpressure — when the channel is full, the flow control logic kicks in (see Section 2.5).

### 2.5 Flow Control

If the encoder output channel is full (network slower than encode rate):
- `try_send` returns `TrySendError::Full` — drop the frame
- Never drop keyframes (IDR) — use unbounded send or dedicated keyframe slot
- Track drop count in periodic Event messages for diagnostics

### 2.6 Server-Side Streaming Architecture

The existing `handle_connection` follows a strict request-response loop and `CapabilityRegistry` handlers return a single `HandlerResult`. To support continuous StreamFrame push, we add a **stream sender mechanism**:

1. Split `Connection` into `ReadHalf` + `WriteHalf` (already supported by transport layer)
2. Wrap `WriteHalf` in `Arc<Mutex<WriteHalf>>`, shared between the response handler and the streaming pipeline
3. Add a new `register_streaming` method on `CapabilityRegistry`:

```rust
impl CapabilityRegistry {
    /// Register a streaming capability handler.
    /// The handler receives params + a StreamSender for pushing frames.
    /// Returns a HandlerResult for the initial response.
    pub fn register_streaming<F>(&self, name: impl Into<String>, handler: F)
    where
        F: Fn(Value, StreamSender) -> Pin<Box<dyn Future<Output = HandlerResult> + Send>>
            + Send + Sync + 'static;
}

/// Sender handle for pushing StreamFrames to the client connection.
pub struct StreamSender {
    write_half: Arc<Mutex<WriteHalf>>,
}

impl StreamSender {
    pub async fn send_frame(&self, frame: StreamFrame) -> Result<(), TransportError>;
}
```

4. `__start_mirror` handler:
   - Creates VT encoder + CADisplayLink capture
   - Spawns a tokio task that reads from the mpsc channel and calls `stream_sender.send_frame()`
   - Returns `{ stream_id }` as the initial response

5. `__stop_mirror` handler:
   - Signals the capture loop and encoder to stop
   - Sends a final `STREAM_END` frame
   - Cleans up resources

### 2.7 Recording State Management

Active recordings are tracked in a `RecordingManager` struct held by `RemoServer`:

```rust
struct RecordingManager {
    active: Option<ActiveRecording>,
    completed: HashMap<String, CompletedRecording>,
}

struct ActiveRecording {
    recording_id: String,
    mode: RecordingMode,  // ReplayKit or VideoToolbox
    file_path: PathBuf,   // /tmp/remo_recording_{id}.mp4
    start_time: Instant,
}

struct CompletedRecording {
    file_path: PathBuf,
    size: u64,
    duration: f64,
}
```

Lifecycle:
- `__start_recording` creates `ActiveRecording`, generates UUID recording_id
- `__stop_recording` finalizes AVAssetWriter, moves entry to `completed` map
- `__download_recording` reads file, sends via BinaryResponse, removes from `completed` map and deletes temp file
- On abnormal termination (connection drop): cleanup task deletes orphaned temp files older than 1 hour in `/tmp/remo_recording_*`

---

## 3. Desktop Receiving & Playback

### 3.1 RpcClient Extension

Read loop in `rpc_client.rs` gains StreamFrame handling:

```rust
Message::StreamFrame(frame) => {
    if let Some(tx) = stream_subs.get(&frame.stream_id) {
        let _ = tx.send(frame);  // broadcast to all subscribers
    }
}
```

New API surface:
```rust
impl RpcClient {
    /// Start mirror stream; returns receiver for frames
    async fn start_mirror(&self, fps: u32, codec: &str) -> Result<StreamReceiver>;

    /// Stop mirror stream
    async fn stop_mirror(&self, stream_id: u32) -> Result<()>;
}

/// Cloneable receiver for stream frames (backed by broadcast channel)
struct StreamReceiver { ... }
impl StreamReceiver {
    async fn next_frame(&mut self) -> Option<StreamFrame>;
}
```

### 3.2 Consumer: MP4 File Writer

`mp4_muxer.rs` — converts H.264 NAL stream to MP4 container:

- Parse SPS/PPS from `CODEC_CONFIG` frames
- Write fMP4 init segment (moov box with avcC, using AVCC length-prefixed format)
- Append moof+mdat segments for each frame group (convert Annex-B to AVCC length-prefixed)
- Use `timestamp_us` from StreamFrame for correct moof timing entries
- Finalize on `STREAM_END` or user stop

### 3.3 Consumer: Web Player

`web_player/` module — local HTTP server for browser-based playback:

**Server (Rust, axum):**
- `GET /` → serve embedded HTML/JS player
- `WS /stream` → WebSocket connection (using axum's built-in WebSocket support), push H.264 frames as binary messages

**Browser (JavaScript):**
- Create `MediaSource` → `SourceBuffer` with codec string derived from SPS bytes (e.g., `video/mp4; codecs="avc1.4D401E"` for Main Profile Level 3.0)
- MSE requires fMP4 segments, not raw H.264 NAL units
- JS-side fMP4 remuxer converts incoming NAL units to fMP4 segments:
  - Receives SPS/PPS → generates init segment (ftyp + moov with avcC in AVCC format)
  - Receives NAL frames → generates media segments (moof + mdat, converting Annex-B start codes to AVCC length prefixes)
- Append segments to SourceBuffer for playback

**Embedded assets:** HTML and JS are `include_str!`/`include_bytes!` compiled into the binary.

### 3.4 CLI Commands

```bash
# Real-time mirror
remo mirror -a 127.0.0.1:9930 --web                    # browser playback
remo mirror -a 127.0.0.1:9930 --save output.mp4        # save to file
remo mirror -a 127.0.0.1:9930 --web --save output.mp4  # both

# Screen recording
remo record start -a 127.0.0.1:9930 --mode replaykit
remo record start -a 127.0.0.1:9930 --mode videotoolbox
remo record stop -a 127.0.0.1:9930 --output recording.mp4
```

---

## 4. File Structure

### New Files

```
crates/remo-objc/src/
├── screen_capture.rs      # CADisplayLink capture loop
├── video_encoder.rs       # VideoToolbox H.264 encoder
├── replay_kit.rs          # ReplayKit capture wrapper
└── recording.rs           # AVAssetWriter local .mp4 recording

crates/remo-sdk/src/
└── streaming.rs           # StreamSender, RecordingManager, streaming handler registration

crates/remo-desktop/src/
├── stream_receiver.rs     # StreamReceiver + broadcast subscription
├── mp4_muxer.rs           # H.264 NAL → MP4 file writer
└── web_player/
    ├── mod.rs             # axum HTTP + WebSocket server
    ├── player.html        # Embedded HTML/JS player (MSE)
    └── fmp4.js            # NAL → fMP4 segment remuxer (Annex-B → AVCC)
```

### Modified Files

| File | Change |
|---|---|
| `crates/remo-protocol/src/message.rs` | Add `StreamFrame` struct (no Serialize/Deserialize), `Message::StreamFrame` variant with `#[serde(skip)]` |
| `crates/remo-protocol/src/codec.rs` | Encode/decode Type 0x02 explicitly before JSON fallback, raise MAX_FRAME_SIZE to 64 MiB |
| `crates/remo-protocol/src/message.rs` | Add `StreamAlreadyActive`, `AuthorizationDenied`, `RecordingNotFound` to `ErrorCode` |
| `crates/remo-sdk/src/server.rs` | Split connection into read/write halves, register 5 new capabilities, integrate RecordingManager |
| `crates/remo-sdk/src/registry.rs` | Add `register_streaming` method, `StreamSender` type |
| `crates/remo-desktop/src/rpc_client.rs` | StreamFrame dispatch to broadcast channel |
| `crates/remo-cli/src/main.rs` | Add `mirror` and `record` subcommands |
| `crates/remo-objc/src/lib.rs` | Export new modules |
| Multiple `Cargo.toml` | New dependencies |

### New Dependencies

| Crate | Purpose | Consumer |
|---|---|---|
| `axum` | HTTP server + WebSocket | remo-desktop |
| `tower-http` | Static file serving | remo-desktop |
| `open` | Auto-open browser | remo-cli |

iOS side (remo-objc) uses no new Rust dependencies — VideoToolbox, ReplayKit, CADisplayLink, AVAssetWriter are all accessed via FFI and objc2.

---

## 5. End-to-End Data Flow

### 5.1 Mirror Stream

```
┌─ iOS App ──────────────────────────────────────────────────────┐
│                                                                │
│  Desktop sends: __start_mirror { fps: 30, codec: "h264" }     │
│                          │                                     │
│                          ▼                                     │
│  Handler returns { stream_id: 1 } + spawns streaming task     │
│                          │                                     │
│  CADisplayLink (30fps) ──► CVPixelBuffer                       │
│       (main thread)         │                                  │
│                             ▼                                  │
│                    VTCompressionSession                         │
│                      (encode thread)                           │
│                             │ try_send() on bounded mpsc       │
│                             ▼                                  │
│                    Tokio task reads mpsc                        │
│                             │                                  │
│                    StreamFrame { stream_id, seq, pts_us, ... } │
│                             │                                  │
│                    stream_sender.send_frame()                  │
│                      (Arc<Mutex<WriteHalf>>)                   │
└─────────────────────────────┼──────────────────────────────────┘
                              │ TCP (localhost / USB tunnel)
┌─ Desktop ───────────────────┼──────────────────────────────────┐
│                             ▼                                  │
│  RpcClient read loop ──► broadcast channel                     │
│                             │                                  │
│              ┌──────────────┼──────────────┐                   │
│              ▼              ▼              ▼                    │
│         MP4 Muxer     Web Player     (future: native window)   │
│         save .mp4     axum server                              │
│                        ├─ GET /  → HTML                        │
│                        └─ WS /stream                           │
│                             │                                  │
│                             ▼                                  │
│                     Browser (MSE)                              │
│                     NAL → fMP4 → SourceBuffer → <video>        │
└────────────────────────────────────────────────────────────────┘
```

### 5.2 Recording

```
Desktop: remo record start --mode replaykit
        │
        ▼
  __start_recording { mode: "replaykit" }
        │
        ▼ (iOS)
  RecordingManager creates ActiveRecording { id: "xxx", path: /tmp/... }
  RPScreenRecorder.startCapture → CMSampleBuffer
        │
        ▼
  AVAssetWriter → /tmp/remo_recording_xxx.mp4
        │
  (user decides to stop)
        │
Desktop: remo record stop --recording-id xxx
        │
        ▼
  __stop_recording { recording_id: "xxx" }
  AVAssetWriter.finishWriting()
  Move to completed map → { recording_id: "xxx", size: N, duration: F }
        │
        ▼
  __download_recording { recording_id: "xxx" }
        │
        ▼
  BinaryResponse (Type 0x01) with .mp4 bytes
  Remove from completed map, delete temp file
        │
        ▼
  CLI writes to output file
```

---

## 6. Design Decisions & Constraints

1. **Flow control**: Bounded `try_send` channel from VT callback to tokio. Drop non-keyframes when full. Never drop IDR frames.
2. **Reconnect**: Client re-sends `__start_mirror`; iOS starts fresh from new keyframe.
3. **Single stream**: One mirror stream at a time (hardware encoder resource constraint). Second request returns `StreamAlreadyActive` error.
4. **Capture source roles**: Mirroring always uses CADisplayLink. Recording uses ReplayKit (system-level) or VideoToolbox (app-level) per user choice. Mirroring + ReplayKit recording run in parallel with independent pipelines. Mirroring + VideoToolbox recording share the CADisplayLink source.
5. **Large file transfer**: MAX_FRAME_SIZE raised to 64 MiB. Recordings exceeding this return an error. Chunked transfer is a future optimization.
6. **NAL format**: Annex-B (start codes) over the wire for simplicity of extraction from VideoToolbox. Consumers (MP4 muxer, JS remuxer) convert to AVCC length-prefixed format as required by fMP4/MSE.
7. **Recording cleanup**: Orphaned temp files in `/tmp/remo_recording_*` older than 1 hour are deleted on server start and periodically.

## 7. Future Work (Out of Scope)

- Native macOS playback window (AVSampleBufferDisplayLayer / Metal)
- SDL/FFmpeg desktop player
- VSCode extension integration
- Wi-Fi support with adaptive bitrate
- H.265/HEVC codec option
- Multi-client mirror streaming
- Chunked file transfer for very large recordings
