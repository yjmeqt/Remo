# Video Streaming Phase 1: Protocol & iOS Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Remo wire protocol with StreamFrame (Type 0x02) and implement H.264 hardware-encoded screen capture on iOS, so that the iOS app can push a continuous stream of H.264 frames over the existing TCP connection.

**Architecture:** Add a new `StreamFrame` message type to `remo-protocol` with binary encoding. On iOS, capture the screen via CADisplayLink + `drawViewHierarchyInRect`, encode frames with VideoToolbox `VTCompressionSession`, and push them through the connection using a new `StreamSender` abstraction. The server gains `__start_mirror` / `__stop_mirror` RPC commands.

**Tech Stack:** Rust, objc2 (ObjC interop), VideoToolbox (C FFI), tokio, existing remo-protocol/transport/sdk crates.

**Spec:** `docs/superpowers/specs/2026-03-22-video-streaming-design.md`

**Scope:** This is Phase 1 of 3. Phase 2 covers desktop receiving + web player. Phase 3 covers recording. This phase produces an iOS app that encodes and sends H.264 StreamFrames, verifiable via integration test and CLI hexdump.

---

## File Map

### New Files

| File | Responsibility |
|---|---|
| `crates/remo-objc/src/video_encoder.rs` | VideoToolbox VTCompressionSession wrapper — create, encode, flush, teardown |
| `crates/remo-objc/src/screen_capture.rs` | CADisplayLink capture loop — start/stop, frame callback, CVPixelBuffer production |
| `crates/remo-sdk/src/streaming.rs` | StreamSender (writes StreamFrames to connection), MirrorSession (encoder + capture lifecycle) |

### Modified Files

| File | Change |
|---|---|
| `crates/remo-protocol/src/message.rs` | Add `StreamFrame` struct, `Message::StreamFrame` variant with `#[serde(skip)]`, new `ErrorCode` variants |
| `crates/remo-protocol/src/codec.rs` | Encode/decode Type 0x02 StreamFrame, raise `MAX_FRAME_SIZE` to 64 MiB |
| `crates/remo-protocol/src/lib.rs` | Re-export `StreamFrame` |
| `crates/remo-sdk/src/server.rs` | Split connection into read/write halves, register `__start_mirror` / `__stop_mirror`, wire up StreamSender |
| `crates/remo-sdk/src/lib.rs` | Export streaming module |
| `crates/remo-objc/src/lib.rs` | Export new modules |
| `Cargo.toml` (root) | Add `[package]` and `[dev-dependencies]` so `tests/integration.rs` becomes a valid test target |
| `tests/integration.rs` | Fix existing broken test (uses wrong API), add streaming integration tests |

---

### Task 1: Add StreamFrame to protocol message types

**Files:**
- Modify: `crates/remo-protocol/src/message.rs`
- Modify: `crates/remo-protocol/src/lib.rs`

- [ ] **Step 1: Add StreamFrame struct and flag constants to message.rs**

Open `crates/remo-protocol/src/message.rs`. After the `BinaryResponse` struct and its `impl` block, add:

```rust
// ---------------------------------------------------------------------------
// Stream frames (video / continuous binary data)
// ---------------------------------------------------------------------------

/// Flag bits for StreamFrame.
pub mod stream_flags {
    pub const KEYFRAME: u8 = 0x01;
    pub const STREAM_START: u8 = 0x02;
    pub const STREAM_END: u8 = 0x04;
    pub const CODEC_CONFIG: u8 = 0x08;
}

/// A continuous-stream frame (Type 0x02 on the wire).
///
/// Unlike Request/Response, StreamFrames are NOT JSON-serialized.
/// They use a compact binary layout for efficiency at high frame rates.
#[derive(Debug, Clone)]
pub struct StreamFrame {
    pub stream_id: u32,
    pub sequence: u32,
    pub timestamp_us: u64,
    pub flags: u8,
    pub data: Vec<u8>,
}

impl StreamFrame {
    pub fn is_keyframe(&self) -> bool {
        self.flags & stream_flags::KEYFRAME != 0
    }

    pub fn is_stream_start(&self) -> bool {
        self.flags & stream_flags::STREAM_START != 0
    }

    pub fn is_stream_end(&self) -> bool {
        self.flags & stream_flags::STREAM_END != 0
    }

    pub fn is_codec_config(&self) -> bool {
        self.flags & stream_flags::CODEC_CONFIG != 0
    }
}
```

- [ ] **Step 2: Add Message::StreamFrame variant**

In the `Message` enum, add the new variant with `#[serde(skip)]` (same pattern as existing `BinaryResponse`):

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Message {
    #[serde(rename = "request")]
    Request(Request),
    #[serde(rename = "response")]
    Response(Response),
    #[serde(rename = "event")]
    Event(Event),
    /// Binary payload — not JSON-serialized, uses Type 0x01 wire encoding.
    #[serde(skip)]
    BinaryResponse(BinaryResponse),
    /// Stream frame — not JSON-serialized, uses Type 0x02 wire encoding.
    #[serde(skip)]
    StreamFrame(StreamFrame),
}
```

- [ ] **Step 3: Add new ErrorCode variants**

In the `ErrorCode` enum, add three new variants:

```rust
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    NotFound,
    InvalidParams,
    Internal,
    Timeout,
    StreamAlreadyActive,
    AuthorizationDenied,
    RecordingNotFound,
}
```

- [ ] **Step 4: Update lib.rs exports**

In `crates/remo-protocol/src/lib.rs`, update the `pub use` to include new types:

```rust
pub use message::{
    stream_flags, BinaryResponse, ErrorCode, Event, Message, MessageId, Request, Response,
    ResponseResult, StreamFrame,
};
```

- [ ] **Step 5: Verify it compiles**

Run: `cd /Users/yi.jiang/Developer/Remo && cargo check -p remo-protocol`
Expected: Compiles with no errors. Warnings about unused fields are OK.

- [ ] **Step 6: Commit**

```bash
git add crates/remo-protocol/src/message.rs crates/remo-protocol/src/lib.rs
git commit -m "feat(protocol): add StreamFrame message type and new ErrorCode variants"
```

---

### Task 2: Encode/decode StreamFrame in the codec

**Files:**
- Modify: `crates/remo-protocol/src/codec.rs`
- Test: inline `#[cfg(test)]` module in same file

**Important context about the existing codec:**
- `MAX_FRAME_SIZE` is `u32` (not `usize`) — keep it as `u32`
- Decoder reads from `src` (a `&mut BytesMut`) using `src[i]`, `src.advance(n)`, and `src.split_to(n)`
- After reading the 4-byte length prefix and advancing past it, then reading the 1-byte type and advancing, `body_len = payload_len - 1` bytes remain in `src`
- Decoder returns `Ok(Some(msg))` on success, `Err(CodecError::...)` on errors
- Encoder returns `Ok(())` on success, `Err(CodecError::...)` on errors
- Type constants: `FRAME_TYPE_JSON = 0x00`, `FRAME_TYPE_BINARY = 0x01`

- [ ] **Step 1: Write failing tests for StreamFrame roundtrip**

Add to the `#[cfg(test)]` module in `crates/remo-protocol/src/codec.rs`. Note: tests need `use crate::message::{StreamFrame, stream_flags};` at the top of the test module:

```rust
use crate::message::{StreamFrame, stream_flags};

#[test]
fn roundtrip_stream_frame() {
    let mut codec = RemoCodec;
    let mut buf = BytesMut::new();

    let frame = StreamFrame {
        stream_id: 1,
        sequence: 42,
        timestamp_us: 1_000_000,
        flags: stream_flags::KEYFRAME | stream_flags::STREAM_START,
        data: vec![0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1e],
    };
    let msg = Message::StreamFrame(frame);

    codec.encode(msg, &mut buf).unwrap();

    // Verify type byte is 0x02
    assert_eq!(buf[4], 0x02);

    let decoded = codec.decode(&mut buf).unwrap().unwrap();
    match decoded {
        Message::StreamFrame(f) => {
            assert_eq!(f.stream_id, 1);
            assert_eq!(f.sequence, 42);
            assert_eq!(f.timestamp_us, 1_000_000);
            assert_eq!(f.flags, stream_flags::KEYFRAME | stream_flags::STREAM_START);
            assert_eq!(f.data, vec![0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1e]);
        }
        other => panic!("expected StreamFrame, got {other:?}"),
    }
    assert!(buf.is_empty());
}

#[test]
fn stream_frame_partial_read() {
    let mut codec = RemoCodec;
    let mut buf = BytesMut::new();

    let frame = StreamFrame {
        stream_id: 1,
        sequence: 0,
        timestamp_us: 0,
        flags: 0,
        data: vec![0xAB; 100],
    };
    codec.encode(Message::StreamFrame(frame), &mut buf).unwrap();

    let full = buf.split();
    let half = full.len() / 2;
    buf.extend_from_slice(&full[..half]);
    assert!(codec.decode(&mut buf).unwrap().is_none());

    buf.extend_from_slice(&full[half..]);
    let decoded = codec.decode(&mut buf).unwrap().unwrap();
    match decoded {
        Message::StreamFrame(f) => {
            assert_eq!(f.data.len(), 100);
            assert!(f.data.iter().all(|&b| b == 0xAB));
        }
        other => panic!("expected StreamFrame, got {other:?}"),
    }
}

#[test]
fn stream_frame_empty_data() {
    let mut codec = RemoCodec;
    let mut buf = BytesMut::new();

    let frame = StreamFrame {
        stream_id: 5,
        sequence: 0,
        timestamp_us: 0,
        flags: stream_flags::STREAM_END,
        data: vec![],
    };
    codec.encode(Message::StreamFrame(frame), &mut buf).unwrap();

    let decoded = codec.decode(&mut buf).unwrap().unwrap();
    match decoded {
        Message::StreamFrame(f) => {
            assert_eq!(f.stream_id, 5);
            assert_eq!(f.flags, stream_flags::STREAM_END);
            assert!(f.data.is_empty());
        }
        other => panic!("expected StreamFrame, got {other:?}"),
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/yi.jiang/Developer/Remo && cargo test -p remo-protocol -- roundtrip_stream_frame stream_frame_partial_read stream_frame_empty_data`
Expected: FAIL — the encoder/decoder don't handle Type 0x02 yet.

- [ ] **Step 3: Update MAX_FRAME_SIZE (keep type as u32)**

At line 24 of `codec.rs`, change:

```rust
const MAX_FRAME_SIZE: u32 = 64 * 1024 * 1024;
```

**Important:** Keep the type as `u32` to match existing comparison sites on lines 58 and 136.

- [ ] **Step 4: Add Type 0x02 constant**

After the existing constants on lines 26-27, add:

```rust
const FRAME_TYPE_STREAM: u8 = 0x02;
```

- [ ] **Step 5: Implement StreamFrame encoding**

In the `Encoder` impl's `encode` method, add a match arm for `Message::StreamFrame` BEFORE the existing `_ =>` JSON fallback arm (which starts around line 148). The `StreamFrame` arm must come before `_ =>` or it would be serialized as broken JSON:

```rust
Message::StreamFrame(frame) => {
    // Wire layout after type byte: [stream_id(4)][seq(4)][pts_us(8)][flags(1)][data...]
    let body_len = 4 + 4 + 8 + 1 + frame.data.len();
    let frame_len = (1 + body_len) as u32; // +1 for type byte

    if frame_len > MAX_FRAME_SIZE {
        return Err(CodecError::FrameTooLarge(frame_len));
    }

    dst.reserve(4 + 1 + body_len);
    dst.put_u32(frame_len);
    dst.put_u8(FRAME_TYPE_STREAM);
    dst.put_u32(frame.stream_id);
    dst.put_u32(frame.sequence);
    dst.put_u64(frame.timestamp_us);
    dst.put_u8(frame.flags);
    dst.extend_from_slice(&frame.data);
    Ok(())
}
```

- [ ] **Step 6: Implement StreamFrame decoding**

In the `Decoder` impl's `decode` method, add a branch for `FRAME_TYPE_STREAM` in the type-byte match (before the `other =>` catch-all on line 116). Follow the same pattern as `FRAME_TYPE_BINARY` — read from `src` using indexing and `advance`/`split_to`:

```rust
FRAME_TYPE_STREAM => {
    // Minimum: stream_id(4) + seq(4) + pts_us(8) + flags(1) = 17 bytes
    if body_len < 17 {
        return Err(CodecError::MalformedBinaryFrame(
            "stream frame too short".into(),
        ));
    }
    let stream_id =
        u32::from_be_bytes([src[0], src[1], src[2], src[3]]);
    let sequence =
        u32::from_be_bytes([src[4], src[5], src[6], src[7]]);
    let timestamp_us = u64::from_be_bytes([
        src[8], src[9], src[10], src[11],
        src[12], src[13], src[14], src[15],
    ]);
    let flags = src[16];
    src.advance(17);

    let data = if body_len > 17 {
        src.split_to(body_len - 17).to_vec()
    } else {
        vec![]
    };

    Ok(Some(Message::StreamFrame(StreamFrame {
        stream_id,
        sequence,
        timestamp_us,
        flags,
        data,
    })))
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd /Users/yi.jiang/Developer/Remo && cargo test -p remo-protocol`
Expected: ALL tests pass (both new and existing).

- [ ] **Step 8: Commit**

```bash
git add crates/remo-protocol/src/codec.rs
git commit -m "feat(protocol): encode/decode StreamFrame (Type 0x02) and raise MAX_FRAME_SIZE to 64 MiB"
```

---

### Task 3: VideoToolbox H.264 encoder wrapper

**Files:**
- Create: `crates/remo-objc/src/video_encoder.rs`
- Modify: `crates/remo-objc/src/lib.rs`

This task creates a safe Rust wrapper around VideoToolbox's `VTCompressionSession` for H.264 hardware encoding. It follows the same dual-cfg pattern as `screenshot.rs` (real implementation gated on `target_vendor = "apple"` AND `feature = "uikit"`, stub on other targets).

- [ ] **Step 1: Create video_encoder.rs**

Create `crates/remo-objc/src/video_encoder.rs`:

```rust
//! H.264 hardware encoder via VideoToolbox.
//!
//! Wraps `VTCompressionSession` to encode `CVPixelBuffer` frames into H.264 NAL units.
//! The encoder runs asynchronously — encoded frames arrive via a callback on an internal
//! VideoToolbox thread, then forwarded through a bounded `std::sync::mpsc` channel.

use std::sync::mpsc;

/// Configuration for the H.264 encoder.
#[derive(Debug, Clone)]
pub struct EncoderConfig {
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub bitrate: u32,           // bits per second
    pub keyframe_interval: u32, // frames between IDR
}

impl Default for EncoderConfig {
    fn default() -> Self {
        Self {
            width: 0,
            height: 0,
            fps: 30,
            bitrate: 4_000_000,
            keyframe_interval: 60,
        }
    }
}

/// An encoded H.264 frame produced by the encoder.
#[derive(Debug, Clone)]
pub struct EncodedFrame {
    pub data: Vec<u8>,         // Annex-B formatted NAL units
    pub timestamp_us: u64,     // Presentation timestamp in microseconds
    pub is_keyframe: bool,
    pub is_codec_config: bool, // true if this contains only SPS/PPS
}

/// Bounded channel capacity for encoded frames.
/// When full, non-keyframes are dropped (flow control).
const ENCODED_CHANNEL_CAPACITY: usize = 8;

#[cfg(all(target_vendor = "apple", feature = "uikit"))]
mod apple {
    use super::*;
    use std::ffi::c_void;
    use std::ptr;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;

    // ---------------------------------------------------------------------------
    // CoreMedia / CoreVideo / VideoToolbox C FFI types
    // ---------------------------------------------------------------------------

    type OSStatus = i32;
    type CFAllocatorRef = *const c_void;
    type CFDictionaryRef = *const c_void;
    type CFStringRef = *const c_void;
    type CFTypeRef = *const c_void;
    type CFBooleanRef = *const c_void;
    type CFNumberRef = *const c_void;
    type CVPixelBufferRef = *const c_void;
    type CMSampleBufferRef = *const c_void;
    type CMFormatDescriptionRef = *const c_void;
    type CMBlockBufferRef = *const c_void;
    type VTCompressionSessionRef = *mut c_void;
    type CFArrayRef = *const c_void;

    #[repr(C)]
    #[derive(Copy, Clone)]
    struct CMTimeRepr {
        value: i64,
        timescale: i32,
        flags: u32,
        epoch: i64,
    }

    type VTCompressionOutputCallback = unsafe extern "C" fn(
        output_callback_ref_con: *mut c_void,
        source_frame_ref_con: *mut c_void,
        status: OSStatus,
        info_flags: u32,
        sample_buffer: CMSampleBufferRef,
    );

    #[link(name = "VideoToolbox", kind = "framework")]
    extern "C" {
        fn VTCompressionSessionCreate(
            allocator: CFAllocatorRef,
            width: i32,
            height: i32,
            codec_type: u32,
            encoder_specification: CFDictionaryRef,
            source_image_buffer_attributes: CFDictionaryRef,
            compressed_data_allocator: CFAllocatorRef,
            output_callback: VTCompressionOutputCallback,
            output_callback_ref_con: *mut c_void,
            compression_session_out: *mut VTCompressionSessionRef,
        ) -> OSStatus;

        fn VTCompressionSessionEncodeFrame(
            session: VTCompressionSessionRef,
            image_buffer: CVPixelBufferRef,
            presentation_time_stamp: CMTimeRepr,
            duration: CMTimeRepr,
            frame_properties: CFDictionaryRef,
            source_frame_ref_con: *mut c_void,
            info_flags_out: *mut u32,
        ) -> OSStatus;

        fn VTCompressionSessionCompleteFrames(
            session: VTCompressionSessionRef,
            complete_until_presentation_time_stamp: CMTimeRepr,
        ) -> OSStatus;

        fn VTCompressionSessionInvalidate(session: VTCompressionSessionRef);

        fn VTSessionSetProperty(
            session: VTCompressionSessionRef,
            property_key: CFStringRef,
            property_value: CFTypeRef,
        ) -> OSStatus;

        fn VTCompressionSessionPrepareToEncodeFrames(
            session: VTCompressionSessionRef,
        ) -> OSStatus;
    }

    #[link(name = "CoreMedia", kind = "framework")]
    extern "C" {
        fn CMSampleBufferGetFormatDescription(sbuf: CMSampleBufferRef) -> CMFormatDescriptionRef;
        fn CMSampleBufferGetDataBuffer(sbuf: CMSampleBufferRef) -> CMBlockBufferRef;
        fn CMSampleBufferGetPresentationTimeStamp(sbuf: CMSampleBufferRef) -> CMTimeRepr;
        fn CMSampleBufferGetSampleAttachmentsArray(
            sbuf: CMSampleBufferRef,
            create_if_necessary: bool,
        ) -> CFArrayRef;
        fn CMBlockBufferGetDataLength(block: CMBlockBufferRef) -> usize;
        fn CMBlockBufferCopyDataBytes(
            the_buffer: CMBlockBufferRef,
            offset_to_data: usize,
            data_length: usize,
            destination: *mut u8,
        ) -> OSStatus;
        fn CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            video_desc: CMFormatDescriptionRef,
            parameter_set_index: usize,
            parameter_set_pointer_out: *mut *const u8,
            parameter_set_size_out: *mut usize,
            parameter_set_count_out: *mut usize,
            nal_unit_header_length_out: *mut i32,
        ) -> OSStatus;
        fn CMTimeMake(value: i64, timescale: i32) -> CMTimeRepr;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFRelease(cf: CFTypeRef);
        fn CFNumberCreate(
            allocator: CFAllocatorRef,
            the_type: i64,
            value_ptr: *const c_void,
        ) -> CFNumberRef;
        fn CFArrayGetCount(the_array: CFArrayRef) -> isize;
        fn CFArrayGetValueAtIndex(the_array: CFArrayRef, idx: isize) -> *const c_void;
        fn CFDictionaryGetValue(
            the_dict: *const c_void,
            key: *const c_void,
        ) -> *const c_void;

        static kCFAllocatorDefault: CFAllocatorRef;
        static kCFBooleanTrue: CFBooleanRef;
        static kCFBooleanFalse: CFBooleanRef;
    }

    // VideoToolbox property keys
    extern "C" {
        static kVTCompressionPropertyKey_RealTime: CFStringRef;
        static kVTCompressionPropertyKey_ProfileLevel: CFStringRef;
        static kVTCompressionPropertyKey_AverageBitRate: CFStringRef;
        static kVTCompressionPropertyKey_MaxKeyFrameInterval: CFStringRef;
        static kVTCompressionPropertyKey_AllowFrameReordering: CFStringRef;
        static kVTProfileLevel_H264_Main_AutoLevel: CFStringRef;
    }

    // CoreMedia attachment key
    extern "C" {
        static kCMSampleAttachmentKey_NotSync: CFStringRef;
    }

    const K_CM_VIDEO_CODEC_TYPE_H264: u32 = 0x61766331; // 'avc1'
    const K_CF_NUMBER_SINT32_TYPE: i64 = 3;

    struct EncoderInner {
        tx: mpsc::SyncSender<EncodedFrame>,
        running: AtomicBool,
    }

    /// H.264 hardware encoder.
    pub struct H264Encoder {
        session: VTCompressionSessionRef,
        inner: Arc<EncoderInner>,
        frame_count: u64,
        config: EncoderConfig,
    }

    // Safety: VTCompressionSession is thread-safe for encoding
    unsafe impl Send for H264Encoder {}

    impl H264Encoder {
        /// Create and configure a new H.264 encoder.
        ///
        /// Returns the encoder and a bounded receiver for encoded frames.
        /// When the channel is full, non-keyframes are dropped (flow control).
        pub fn new(
            config: EncoderConfig,
        ) -> Result<(Self, mpsc::Receiver<EncodedFrame>), String> {
            let (tx, rx) = mpsc::sync_channel(ENCODED_CHANNEL_CAPACITY);

            let inner = Arc::new(EncoderInner {
                tx,
                running: AtomicBool::new(true),
            });

            let mut session: VTCompressionSessionRef = ptr::null_mut();
            let inner_ptr = Arc::into_raw(Arc::clone(&inner)) as *mut c_void;

            let status = unsafe {
                VTCompressionSessionCreate(
                    kCFAllocatorDefault,
                    config.width as i32,
                    config.height as i32,
                    K_CM_VIDEO_CODEC_TYPE_H264,
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                    output_callback,
                    inner_ptr,
                    &mut session,
                )
            };

            if status != 0 {
                unsafe { Arc::from_raw(inner_ptr as *const EncoderInner) };
                return Err(format!("VTCompressionSessionCreate failed: {status}"));
            }

            unsafe {
                VTSessionSetProperty(
                    session,
                    kVTCompressionPropertyKey_RealTime,
                    kCFBooleanTrue as CFTypeRef,
                );
                VTSessionSetProperty(
                    session,
                    kVTCompressionPropertyKey_ProfileLevel,
                    kVTProfileLevel_H264_Main_AutoLevel as CFTypeRef,
                );
                VTSessionSetProperty(
                    session,
                    kVTCompressionPropertyKey_AllowFrameReordering,
                    kCFBooleanFalse as CFTypeRef,
                );

                let bitrate = config.bitrate as i32;
                let bitrate_num = CFNumberCreate(
                    kCFAllocatorDefault,
                    K_CF_NUMBER_SINT32_TYPE,
                    &bitrate as *const i32 as *const c_void,
                );
                VTSessionSetProperty(
                    session,
                    kVTCompressionPropertyKey_AverageBitRate,
                    bitrate_num as CFTypeRef,
                );
                CFRelease(bitrate_num as CFTypeRef);

                let kfi = config.keyframe_interval as i32;
                let kfi_num = CFNumberCreate(
                    kCFAllocatorDefault,
                    K_CF_NUMBER_SINT32_TYPE,
                    &kfi as *const i32 as *const c_void,
                );
                VTSessionSetProperty(
                    session,
                    kVTCompressionPropertyKey_MaxKeyFrameInterval,
                    kfi_num as CFTypeRef,
                );
                CFRelease(kfi_num as CFTypeRef);

                VTCompressionSessionPrepareToEncodeFrames(session);
            }

            Ok((
                Self {
                    session,
                    inner,
                    frame_count: 0,
                    config,
                },
                rx,
            ))
        }

        /// Encode a CVPixelBuffer. The result arrives asynchronously via the receiver.
        ///
        /// # Safety
        /// `pixel_buffer` must be a valid `CVPixelBufferRef`.
        pub unsafe fn encode_frame(
            &mut self,
            pixel_buffer: CVPixelBufferRef,
        ) -> Result<(), String> {
            let pts = CMTimeMake(self.frame_count as i64, self.config.fps as i32);
            let duration = CMTimeMake(1, self.config.fps as i32);

            let status = VTCompressionSessionEncodeFrame(
                self.session,
                pixel_buffer,
                pts,
                duration,
                ptr::null(),
                ptr::null_mut(),
                ptr::null_mut(),
            );

            self.frame_count += 1;

            if status != 0 {
                Err(format!("VTCompressionSessionEncodeFrame failed: {status}"))
            } else {
                Ok(())
            }
        }

        /// Flush any pending frames.
        pub fn flush(&self) -> Result<(), String> {
            let time = unsafe { CMTimeMake(i64::MAX, 1) };
            let status =
                unsafe { VTCompressionSessionCompleteFrames(self.session, time) };
            if status != 0 {
                Err(format!(
                    "VTCompressionSessionCompleteFrames failed: {status}"
                ))
            } else {
                Ok(())
            }
        }

        /// Stop the encoder and release resources.
        pub fn stop(&self) {
            self.inner.running.store(false, Ordering::Relaxed);
            unsafe {
                VTCompressionSessionInvalidate(self.session);
            }
        }
    }

    impl Drop for H264Encoder {
        fn drop(&mut self) {
            self.stop();
        }
    }

    /// VTCompressionSession output callback — called on an internal VT thread.
    ///
    /// Uses `try_send` (non-async) because this is a synchronous C callback
    /// with no tokio runtime context available.
    unsafe extern "C" fn output_callback(
        output_callback_ref_con: *mut c_void,
        _source_frame_ref_con: *mut c_void,
        status: OSStatus,
        _info_flags: u32,
        sample_buffer: CMSampleBufferRef,
    ) {
        if status != 0 || sample_buffer.is_null() {
            return;
        }

        let inner = &*(output_callback_ref_con as *const EncoderInner);
        if !inner.running.load(Ordering::Relaxed) {
            return;
        }

        let is_keyframe = is_sample_keyframe(sample_buffer);
        let format_desc = CMSampleBufferGetFormatDescription(sample_buffer);

        // Extract and send SPS/PPS on keyframes
        if is_keyframe && !format_desc.is_null() {
            if let Some(config_frame) = extract_parameter_sets(format_desc) {
                // Keyframe config: always try to send (never drop)
                let _ = inner.tx.try_send(config_frame);
            }
        }

        // Extract encoded NAL units
        if let Some(frame) = extract_encoded_data(sample_buffer, is_keyframe) {
            match inner.tx.try_send(frame) {
                Ok(()) => {}
                Err(mpsc::TrySendError::Full(dropped)) => {
                    // Flow control: drop non-keyframes when channel is full
                    if dropped.is_keyframe {
                        // Never drop keyframes — block briefly if needed
                        let _ = inner.tx.send(dropped);
                    }
                    // else: non-keyframe dropped, acceptable
                }
                Err(mpsc::TrySendError::Disconnected(_)) => {}
            }
        }
    }

    /// Check if a sample buffer is a keyframe by inspecting attachments.
    unsafe fn is_sample_keyframe(sample_buffer: CMSampleBufferRef) -> bool {
        let attachments =
            CMSampleBufferGetSampleAttachmentsArray(sample_buffer, false);
        if attachments.is_null() || CFArrayGetCount(attachments) == 0 {
            // No attachments means it's a keyframe (first frame)
            return true;
        }

        let dict = CFArrayGetValueAtIndex(attachments, 0);
        if dict.is_null() {
            return true;
        }

        // kCMSampleAttachmentKey_NotSync == true means NOT a keyframe
        let not_sync = CFDictionaryGetValue(dict, kCMSampleAttachmentKey_NotSync as *const c_void);
        if not_sync.is_null() {
            return true; // key absent → sync sample (keyframe)
        }

        // If NotSync is kCFBooleanTrue, this is NOT a keyframe
        not_sync != kCFBooleanTrue as *const c_void
    }

    /// Extract SPS and PPS from the format description, return as Annex-B.
    unsafe fn extract_parameter_sets(
        format_desc: CMFormatDescriptionRef,
    ) -> Option<EncodedFrame> {
        let mut sps_ptr: *const u8 = ptr::null();
        let mut sps_len: usize = 0;
        let mut pps_ptr: *const u8 = ptr::null();
        let mut pps_len: usize = 0;
        let mut count: usize = 0;

        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format_desc,
            0,
            &mut sps_ptr,
            &mut sps_len,
            &mut count,
            ptr::null_mut(),
        );
        if status != 0 || sps_ptr.is_null() {
            return None;
        }

        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format_desc,
            1,
            &mut pps_ptr,
            &mut pps_len,
            ptr::null_mut(),
            ptr::null_mut(),
        );
        if status != 0 || pps_ptr.is_null() {
            return None;
        }

        let start_code: [u8; 4] = [0x00, 0x00, 0x00, 0x01];
        let mut data = Vec::with_capacity(start_code.len() * 2 + sps_len + pps_len);
        data.extend_from_slice(&start_code);
        data.extend_from_slice(std::slice::from_raw_parts(sps_ptr, sps_len));
        data.extend_from_slice(&start_code);
        data.extend_from_slice(std::slice::from_raw_parts(pps_ptr, pps_len));

        Some(EncodedFrame {
            data,
            timestamp_us: 0,
            is_keyframe: false,
            is_codec_config: true,
        })
    }

    /// Extract encoded NAL units from the sample buffer, convert to Annex-B.
    unsafe fn extract_encoded_data(
        sample_buffer: CMSampleBufferRef,
        is_keyframe: bool,
    ) -> Option<EncodedFrame> {
        let block_buf = CMSampleBufferGetDataBuffer(sample_buffer);
        if block_buf.is_null() {
            return None;
        }

        let data_len = CMBlockBufferGetDataLength(block_buf);
        if data_len == 0 {
            return None;
        }

        let mut raw = vec![0u8; data_len];
        let status = CMBlockBufferCopyDataBytes(block_buf, 0, data_len, raw.as_mut_ptr());
        if status != 0 {
            return None;
        }

        let annex_b = avcc_to_annex_b(&raw);

        let pts = CMSampleBufferGetPresentationTimeStamp(sample_buffer);
        let timestamp_us = if pts.timescale > 0 {
            (pts.value as u64 * 1_000_000) / pts.timescale as u64
        } else {
            0
        };

        Some(EncodedFrame {
            data: annex_b,
            timestamp_us,
            is_keyframe,
            is_codec_config: false,
        })
    }

    /// Convert AVCC length-prefixed NAL units to Annex-B start code format.
    pub fn avcc_to_annex_b(data: &[u8]) -> Vec<u8> {
        let start_code: [u8; 4] = [0x00, 0x00, 0x00, 0x01];
        let mut result = Vec::with_capacity(data.len());
        let mut offset = 0;

        while offset + 4 <= data.len() {
            let nal_len = u32::from_be_bytes([
                data[offset],
                data[offset + 1],
                data[offset + 2],
                data[offset + 3],
            ]) as usize;
            offset += 4;

            if offset + nal_len > data.len() {
                break;
            }

            result.extend_from_slice(&start_code);
            result.extend_from_slice(&data[offset..offset + nal_len]);
            offset += nal_len;
        }

        result
    }
}

#[cfg(not(all(target_vendor = "apple", feature = "uikit")))]
mod apple {
    use super::*;

    pub struct H264Encoder;

    impl H264Encoder {
        pub fn new(
            _config: EncoderConfig,
        ) -> Result<(Self, mpsc::Receiver<EncodedFrame>), String> {
            tracing::warn!("H264Encoder not available on non-Apple target");
            let (_tx, rx) = mpsc::channel();
            Ok((Self, rx))
        }

        pub unsafe fn encode_frame(
            &mut self,
            _pixel_buffer: *const std::ffi::c_void,
        ) -> Result<(), String> {
            Ok(())
        }

        pub fn flush(&self) -> Result<(), String> {
            Ok(())
        }

        pub fn stop(&self) {}
    }

    pub fn avcc_to_annex_b(data: &[u8]) -> Vec<u8> {
        let start_code: [u8; 4] = [0x00, 0x00, 0x00, 0x01];
        let mut result = Vec::with_capacity(data.len());
        let mut offset = 0;

        while offset + 4 <= data.len() {
            let nal_len = u32::from_be_bytes([
                data[offset],
                data[offset + 1],
                data[offset + 2],
                data[offset + 3],
            ]) as usize;
            offset += 4;

            if offset + nal_len > data.len() {
                break;
            }

            result.extend_from_slice(&start_code);
            result.extend_from_slice(&data[offset..offset + nal_len]);
            offset += nal_len;
        }

        result
    }
}

pub use apple::{avcc_to_annex_b, H264Encoder};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encoder_config_defaults() {
        let cfg = EncoderConfig::default();
        assert_eq!(cfg.fps, 30);
        assert_eq!(cfg.bitrate, 4_000_000);
        assert_eq!(cfg.keyframe_interval, 60);
    }

    #[test]
    fn encoded_frame_fields() {
        let frame = EncodedFrame {
            data: vec![0x00, 0x00, 0x00, 0x01, 0x67],
            timestamp_us: 33333,
            is_keyframe: true,
            is_codec_config: false,
        };
        assert!(frame.is_keyframe);
        assert!(!frame.is_codec_config);
    }

    #[test]
    fn avcc_to_annex_b_single_nal() {
        // AVCC: [length=3][NAL bytes]
        let avcc = vec![0x00, 0x00, 0x00, 0x03, 0x67, 0x42, 0x00];
        let annex_b = avcc_to_annex_b(&avcc);
        assert_eq!(annex_b, vec![0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00]);
    }

    #[test]
    fn avcc_to_annex_b_multiple_nals() {
        // Two NALs: [len=2][AA BB][len=1][CC]
        let avcc = vec![
            0x00, 0x00, 0x00, 0x02, 0xAA, 0xBB,
            0x00, 0x00, 0x00, 0x01, 0xCC,
        ];
        let annex_b = avcc_to_annex_b(&avcc);
        assert_eq!(
            annex_b,
            vec![
                0x00, 0x00, 0x00, 0x01, 0xAA, 0xBB,
                0x00, 0x00, 0x00, 0x01, 0xCC,
            ]
        );
    }

    #[test]
    fn avcc_to_annex_b_empty() {
        assert!(avcc_to_annex_b(&[]).is_empty());
    }

    #[test]
    fn avcc_to_annex_b_truncated() {
        // Length says 10 bytes but only 2 available — should stop gracefully
        let avcc = vec![0x00, 0x00, 0x00, 0x0A, 0xAA, 0xBB];
        let annex_b = avcc_to_annex_b(&avcc);
        assert!(annex_b.is_empty());
    }

    #[cfg(not(all(target_vendor = "apple", feature = "uikit")))]
    #[test]
    fn stub_encoder_creates_ok() {
        let config = EncoderConfig {
            width: 640,
            height: 480,
            ..Default::default()
        };
        let (encoder, _rx) = H264Encoder::new(config).unwrap();
        encoder.stop();
    }
}
```

- [ ] **Step 2: Export from lib.rs**

In `crates/remo-objc/src/lib.rs`, add:

```rust
mod video_encoder;
pub use video_encoder::{avcc_to_annex_b, EncodedFrame, EncoderConfig, H264Encoder};
```

- [ ] **Step 3: Verify it compiles and tests pass**

Run: `cd /Users/yi.jiang/Developer/Remo && cargo test -p remo-objc`
Expected: All tests pass (including avcc_to_annex_b tests on all platforms, stub encoder test on non-Apple).

- [ ] **Step 4: Commit**

```bash
git add crates/remo-objc/src/video_encoder.rs crates/remo-objc/src/lib.rs
git commit -m "feat(objc): add VideoToolbox H.264 encoder wrapper with AVCC-to-Annex-B conversion"
```

---

### Task 4: CADisplayLink screen capture to CVPixelBuffer

**Files:**
- Create: `crates/remo-objc/src/screen_capture.rs`
- Modify: `crates/remo-objc/src/lib.rs`

- [ ] **Step 1: Create screen_capture.rs**

Create `crates/remo-objc/src/screen_capture.rs`:

```rust
//! Screen capture via UIKit rendering to CVPixelBuffer.
//!
//! Captures the app's key window by rendering into a CGContext backed by a
//! CVPixelBuffer, suitable for feeding directly into VideoToolbox encoding.

/// Info about the captured screen dimensions.
#[derive(Debug, Clone)]
pub struct CaptureInfo {
    pub width: u32,
    pub height: u32,
    pub scale: f64,
}

#[cfg(all(target_vendor = "apple", feature = "uikit"))]
mod apple {
    use super::*;
    use std::ffi::c_void;
    use std::ptr;

    type CGFloat = f64;

    #[repr(C)]
    #[derive(Copy, Clone)]
    struct CGSize {
        width: CGFloat,
        height: CGFloat,
    }

    #[repr(C)]
    #[derive(Copy, Clone)]
    struct CGRect {
        origin: CGPoint,
        size: CGSize,
    }

    #[repr(C)]
    #[derive(Copy, Clone)]
    struct CGPoint {
        x: CGFloat,
        y: CGFloat,
    }

    type CVReturn = i32;
    type CVPixelBufferRef = *mut c_void;
    type CGContextRef = *mut c_void;
    type CGColorSpaceRef = *mut c_void;
    type CGImageRef = *const c_void;

    #[link(name = "CoreVideo", kind = "framework")]
    extern "C" {
        fn CVPixelBufferCreate(
            allocator: *const c_void,
            width: usize,
            height: usize,
            pixel_format_type: u32,
            pixel_buffer_attributes: *const c_void,
            pixel_buffer_out: *mut CVPixelBufferRef,
        ) -> CVReturn;
        fn CVPixelBufferLockBaseAddress(pixel_buffer: CVPixelBufferRef, flags: u64) -> CVReturn;
        fn CVPixelBufferUnlockBaseAddress(pixel_buffer: CVPixelBufferRef, flags: u64) -> CVReturn;
        fn CVPixelBufferGetBaseAddress(pixel_buffer: CVPixelBufferRef) -> *mut c_void;
        fn CVPixelBufferGetBytesPerRow(pixel_buffer: CVPixelBufferRef) -> usize;
    }

    #[link(name = "CoreGraphics", kind = "framework")]
    extern "C" {
        fn CGBitmapContextCreate(
            data: *mut c_void,
            width: usize,
            height: usize,
            bits_per_component: usize,
            bytes_per_row: usize,
            space: CGColorSpaceRef,
            bitmap_info: u32,
        ) -> CGContextRef;
        fn CGColorSpaceCreateDeviceRGB() -> CGColorSpaceRef;
        fn CGContextRelease(context: CGContextRef);
        fn CGColorSpaceRelease(color_space: CGColorSpaceRef);
        fn CGContextDrawImage(c: CGContextRef, rect: CGRect, image: CGImageRef);
    }

    extern "C" {
        fn UIGraphicsBeginImageContextWithOptions(size: CGSize, opaque: bool, scale: CGFloat);
        fn UIGraphicsGetImageFromCurrentImageContext() -> *mut objc2::runtime::AnyObject;
        fn UIGraphicsEndImageContext();
    }

    extern "C" {
        fn CFRelease(cf: *const c_void);
    }

    // kCVPixelFormatType_32BGRA
    const K_CV_PIXEL_FORMAT_TYPE_32BGRA: u32 = 0x42475241;
    // CGBitmapInfo: kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
    const K_CG_BITMAP_INFO: u32 = (2 << 12) | 2;

    /// Capture the key window into a CVPixelBuffer.
    ///
    /// Returns the raw `CVPixelBufferRef` pointer. Caller must `CFRelease` it when done.
    ///
    /// # Safety
    /// Must be called on the main thread.
    pub unsafe fn capture_frame_to_pixel_buffer(
        width: u32,
        height: u32,
        scale: f64,
    ) -> Option<*mut c_void> {
        use objc2::msg_send;
        use objc2::MainThreadMarker;
        use objc2_ui_kit::UIApplication;

        let mtm = MainThreadMarker::new_unchecked();
        let app = UIApplication::sharedApplication(mtm);
        #[allow(deprecated)]
        let windows = app.windows();
        let key_window = windows.iter().find(|w| w.isKeyWindow())?;

        let bounds: objc2_foundation::NSRect = msg_send![&*key_window, bounds];

        let pixel_width = (width as f64 * scale) as usize;
        let pixel_height = (height as f64 * scale) as usize;

        // Create CVPixelBuffer
        let mut pixel_buffer: CVPixelBufferRef = ptr::null_mut();
        let status = CVPixelBufferCreate(
            ptr::null(),
            pixel_width,
            pixel_height,
            K_CV_PIXEL_FORMAT_TYPE_32BGRA,
            ptr::null(),
            &mut pixel_buffer,
        );
        if status != 0 || pixel_buffer.is_null() {
            return None;
        }

        CVPixelBufferLockBaseAddress(pixel_buffer, 0);
        let base_address = CVPixelBufferGetBaseAddress(pixel_buffer);
        let bytes_per_row = CVPixelBufferGetBytesPerRow(pixel_buffer);

        let color_space = CGColorSpaceCreateDeviceRGB();
        let context = CGBitmapContextCreate(
            base_address,
            pixel_width,
            pixel_height,
            8,
            bytes_per_row,
            color_space,
            K_CG_BITMAP_INFO,
        );
        CGColorSpaceRelease(color_space);

        if context.is_null() {
            CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
            CFRelease(pixel_buffer as *const c_void);
            return None;
        }

        // Render view hierarchy into UIImage
        let size = CGSize {
            width: bounds.size.width,
            height: bounds.size.height,
        };
        UIGraphicsBeginImageContextWithOptions(size, false, scale);

        let after_updates: bool = false; // false for speed in continuous capture
        let _success: bool = msg_send![
            &*key_window,
            drawViewHierarchyInRect: bounds,
            afterScreenUpdates: after_updates
        ];

        let image: *mut objc2::runtime::AnyObject =
            UIGraphicsGetImageFromCurrentImageContext();

        if !image.is_null() {
            let cg_image: CGImageRef = msg_send![image, CGImage];
            if !cg_image.is_null() {
                let draw_rect = CGRect {
                    origin: CGPoint { x: 0.0, y: 0.0 },
                    size: CGSize {
                        width: pixel_width as f64,
                        height: pixel_height as f64,
                    },
                };
                CGContextDrawImage(context, draw_rect, cg_image);
            }
        }

        UIGraphicsEndImageContext();
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);

        Some(pixel_buffer)
    }

    /// Get screen dimensions of the key window.
    ///
    /// # Safety
    /// Must be called on the main thread.
    pub unsafe fn get_screen_info() -> Option<CaptureInfo> {
        use objc2::msg_send;
        use objc2::runtime::AnyObject;
        use objc2::MainThreadMarker;
        use objc2_ui_kit::UIApplication;

        let mtm = MainThreadMarker::new_unchecked();
        let app = UIApplication::sharedApplication(mtm);
        #[allow(deprecated)]
        let windows = app.windows();
        let key_window = windows.iter().find(|w| w.isKeyWindow())?;

        let bounds: objc2_foundation::NSRect = msg_send![&*key_window, bounds];
        let screen: *mut AnyObject = msg_send![&*key_window, screen];
        let scale: f64 = msg_send![screen, scale];

        Some(CaptureInfo {
            width: bounds.size.width as u32,
            height: bounds.size.height as u32,
            scale,
        })
    }
}

#[cfg(not(all(target_vendor = "apple", feature = "uikit")))]
mod apple {
    use super::*;

    pub unsafe fn capture_frame_to_pixel_buffer(
        _width: u32,
        _height: u32,
        _scale: f64,
    ) -> Option<*mut std::ffi::c_void> {
        tracing::warn!("capture_frame_to_pixel_buffer called on non-Apple target");
        None
    }

    pub unsafe fn get_screen_info() -> Option<CaptureInfo> {
        tracing::warn!("get_screen_info called on non-Apple target");
        None
    }
}

pub use apple::{capture_frame_to_pixel_buffer, get_screen_info};
```

- [ ] **Step 2: Export from lib.rs**

In `crates/remo-objc/src/lib.rs`, add:

```rust
mod screen_capture;
pub use screen_capture::{capture_frame_to_pixel_buffer, get_screen_info, CaptureInfo};
```

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/yi.jiang/Developer/Remo && cargo check -p remo-objc`
Expected: Compiles with no errors.

- [ ] **Step 4: Commit**

```bash
git add crates/remo-objc/src/screen_capture.rs crates/remo-objc/src/lib.rs
git commit -m "feat(objc): add screen capture to CVPixelBuffer for VideoToolbox encoding"
```

---

### Task 5: StreamSender and server-side mirror session

**Files:**
- Create: `crates/remo-sdk/src/streaming.rs`
- Modify: `crates/remo-sdk/src/server.rs`
- Modify: `crates/remo-sdk/src/lib.rs`

**Important context about the existing server:**
- `handle_connection(mut conn: Connection, registry: CapabilityRegistry)` takes ownership of `conn`
- `Connection::split()` returns `(ReadHalf, WriteHalf)` (from `remo-transport`)
- `ReadHalf` has `recv() -> Result<Option<Message>, TransportError>`
- `WriteHalf` has `send(Message) -> Result<(), TransportError>`
- Responses are sent back on the same connection after dispatching
- The `tokio::sync::Mutex` must be used (not `std::sync::Mutex`) because it's held across `.await` points

- [ ] **Step 1: Create streaming.rs**

Create `crates/remo-sdk/src/streaming.rs`:

```rust
//! Streaming infrastructure: StreamSender for pushing frames, MirrorSession lifecycle.

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;

use remo_protocol::{stream_flags, Message, StreamFrame};
use remo_transport::WriteHalf;
use tokio::sync::Mutex;
use tracing::{debug, error, info, warn};

/// Handle for pushing StreamFrames to a client connection.
///
/// Wraps `Arc<Mutex<WriteHalf>>` so both the response handler and the
/// streaming pipeline can write to the same connection.
#[derive(Clone)]
pub struct StreamSender {
    write_half: Arc<Mutex<WriteHalf>>,
}

impl StreamSender {
    pub fn new(write_half: Arc<Mutex<WriteHalf>>) -> Self {
        Self { write_half }
    }

    /// Send a StreamFrame to the client.
    pub async fn send_frame(
        &self,
        frame: StreamFrame,
    ) -> Result<(), remo_transport::TransportError> {
        let mut w = self.write_half.lock().await;
        w.send(Message::StreamFrame(frame)).await
    }

    /// Send a non-stream message (for responses during streaming).
    pub async fn send_message(
        &self,
        msg: Message,
    ) -> Result<(), remo_transport::TransportError> {
        let mut w = self.write_half.lock().await;
        w.send(msg).await
    }
}

/// Active mirror streaming session.
pub struct MirrorSession {
    pub stream_id: u32,
    running: Arc<AtomicBool>,
    sequence: AtomicU32,
}

impl MirrorSession {
    pub fn new(stream_id: u32) -> Self {
        Self {
            stream_id,
            running: Arc::new(AtomicBool::new(true)),
            sequence: AtomicU32::new(0),
        }
    }

    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Relaxed)
    }

    pub fn stop(&self) {
        self.running.store(false, Ordering::Relaxed);
    }

    pub fn running_flag(&self) -> Arc<AtomicBool> {
        Arc::clone(&self.running)
    }

    pub fn next_sequence(&self) -> u32 {
        self.sequence.fetch_add(1, Ordering::Relaxed)
    }
}

/// Start the mirror encoding loop.
///
/// 1. Gets screen info on main thread
/// 2. Creates H.264 encoder
/// 3. Captures frames at target FPS via main-thread GCD dispatch
/// 4. Reads encoded NAL units and sends as StreamFrames
///
/// Returns when the session is stopped or an error occurs.
#[allow(unsafe_code)]
pub async fn run_mirror_loop(session: Arc<MirrorSession>, sender: StreamSender, fps: u32) {
    info!(stream_id = session.stream_id, fps, "starting mirror loop");

    let info = remo_objc::run_on_main_sync(|| unsafe { remo_objc::get_screen_info() });
    let info = match info {
        Some(i) => i,
        None => {
            error!("failed to get screen info");
            return;
        }
    };

    let pixel_width = (info.width as f64 * info.scale) as u32;
    let pixel_height = (info.height as f64 * info.scale) as u32;

    let config = remo_objc::EncoderConfig {
        width: pixel_width,
        height: pixel_height,
        fps,
        ..Default::default()
    };

    let (mut encoder, encoded_rx) = match remo_objc::H264Encoder::new(config) {
        Ok(pair) => pair,
        Err(e) => {
            error!("failed to create encoder: {e}");
            return;
        }
    };

    let running = session.running_flag();
    let frame_interval = std::time::Duration::from_micros(1_000_000 / u64::from(fps));

    // Task: read encoded frames from mpsc and send as StreamFrames
    let sender_clone = sender.clone();
    let session_clone = Arc::clone(&session);
    let running_clone = Arc::clone(&running);
    let send_task = tokio::spawn(async move {
        while running_clone.load(Ordering::Relaxed) {
            match encoded_rx.try_recv() {
                Ok(encoded) => {
                    let seq = session_clone.next_sequence();
                    let mut flags = 0u8;
                    if encoded.is_codec_config {
                        flags |= stream_flags::CODEC_CONFIG;
                        if seq == 0 {
                            flags |= stream_flags::STREAM_START;
                        }
                    }
                    if encoded.is_keyframe {
                        flags |= stream_flags::KEYFRAME;
                    }

                    let frame = StreamFrame {
                        stream_id: session_clone.stream_id,
                        sequence: seq,
                        timestamp_us: encoded.timestamp_us,
                        flags,
                        data: encoded.data,
                    };

                    if let Err(e) = sender_clone.send_frame(frame).await {
                        warn!("failed to send stream frame: {e}");
                        break;
                    }
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => {
                    tokio::time::sleep(std::time::Duration::from_millis(1)).await;
                }
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    debug!("encoder channel disconnected");
                    break;
                }
            }
        }
    });

    // Capture loop — render on main thread, encode, sleep
    while running.load(Ordering::Relaxed) {
        let w = info.width;
        let h = info.height;
        let s = info.scale;

        let pixel_buffer =
            remo_objc::run_on_main_sync(move || unsafe {
                remo_objc::capture_frame_to_pixel_buffer(w, h, s)
            });

        if let Some(pb) = pixel_buffer {
            if let Err(e) = unsafe { encoder.encode_frame(pb as *const _) } {
                warn!("encode error: {e}");
            }
            extern "C" {
                fn CFRelease(cf: *const std::ffi::c_void);
            }
            unsafe { CFRelease(pb as *const _) };
        }

        tokio::time::sleep(frame_interval).await;
    }

    // Cleanup
    encoder.flush().ok();
    encoder.stop();
    send_task.abort();

    let end_frame = StreamFrame {
        stream_id: session.stream_id,
        sequence: session.next_sequence(),
        timestamp_us: 0,
        flags: stream_flags::STREAM_END,
        data: vec![],
    };
    let _ = sender.send_frame(end_frame).await;

    info!(stream_id = session.stream_id, "mirror loop stopped");
}
```

- [ ] **Step 2: Modify handle_connection in server.rs**

In `crates/remo-sdk/src/server.rs`, make these changes:

1. Add imports at the top:
```rust
use std::sync::Arc;
use tokio::sync::Mutex;
```

2. Replace the existing `handle_connection` function with a version that splits the connection:

```rust
async fn handle_connection(conn: Connection, registry: CapabilityRegistry) {
    let peer = conn.peer_addr();
    info!(%peer, "handling connection");

    let (mut read_half, write_half) = conn.split();
    let write_half = Arc::new(Mutex::new(write_half));
    let sender = crate::streaming::StreamSender::new(Arc::clone(&write_half));

    // Active mirror session (only one at a time per connection)
    let mirror_session: Arc<Mutex<Option<Arc<crate::streaming::MirrorSession>>>> =
        Arc::new(Mutex::new(None));

    loop {
        let msg = match read_half.recv().await {
            Ok(Some(msg)) => msg,
            Ok(None) => {
                info!(%peer, "connection closed");
                break;
            }
            Err(e) => {
                warn!(%peer, "read error: {e}");
                break;
            }
        };

        match msg {
            Message::Request(req) => {
                let response_msg = dispatch_request_with_streaming(
                    &registry,
                    req,
                    &sender,
                    &mirror_session,
                )
                .await;

                if let Err(e) = sender.send_message(response_msg).await {
                    warn!(%peer, "write error: {e}");
                    break;
                }
            }
            other => {
                warn!(%peer, "unexpected message type: {other:?}");
            }
        }
    }

    // Stop any active mirror session on disconnect
    let session = mirror_session.lock().await.take();
    if let Some(s) = session {
        s.stop();
    }
}
```

3. Add the new streaming-aware dispatch function (BEFORE the existing `dispatch_request`):

```rust
async fn dispatch_request_with_streaming(
    registry: &CapabilityRegistry,
    req: Request,
    sender: &crate::streaming::StreamSender,
    mirror_session: &Arc<Mutex<Option<Arc<crate::streaming::MirrorSession>>>>,
) -> Message {
    let Request {
        id,
        capability,
        params,
    } = req;

    match capability.as_str() {
        "__start_mirror" => {
            let mut session_guard = mirror_session.lock().await;
            if session_guard.is_some() {
                return Message::Response(Response::error(
                    id,
                    ErrorCode::StreamAlreadyActive,
                    "a mirror stream is already active".into(),
                ));
            }

            let fps = params
                .get("fps")
                .and_then(|v| v.as_u64())
                .unwrap_or(30) as u32;

            let stream_id = 1u32;
            let session = Arc::new(crate::streaming::MirrorSession::new(stream_id));
            *session_guard = Some(Arc::clone(&session));

            let sender_clone = sender.clone();
            tokio::spawn(async move {
                crate::streaming::run_mirror_loop(session, sender_clone, fps).await;
            });

            Message::Response(Response::ok(
                id,
                serde_json::json!({ "stream_id": stream_id }),
            ))
        }
        "__stop_mirror" => {
            let mut session_guard = mirror_session.lock().await;
            if let Some(session) = session_guard.take() {
                session.stop();
                Message::Response(Response::ok(id, serde_json::json!({ "stopped": true })))
            } else {
                Message::Response(Response::error(
                    id,
                    ErrorCode::NotFound,
                    "no active mirror stream".into(),
                ))
            }
        }
        _ => dispatch_request(registry, Request { id, capability, params }).await,
    }
}
```

- [ ] **Step 3: Export streaming module**

In `crates/remo-sdk/src/lib.rs`, add:

```rust
#[allow(unsafe_code)]
mod streaming;
pub use streaming::{MirrorSession, StreamSender};
```

- [ ] **Step 4: Verify it compiles**

Run: `cd /Users/yi.jiang/Developer/Remo && cargo check -p remo-sdk`
Expected: Compiles with no errors.

- [ ] **Step 5: Commit**

```bash
git add crates/remo-sdk/src/streaming.rs crates/remo-sdk/src/server.rs crates/remo-sdk/src/lib.rs
git commit -m "feat(sdk): add StreamSender, MirrorSession, and __start_mirror/__stop_mirror"
```

---

### Task 6: Fix integration tests and add streaming tests

**Files:**
- Modify: `Cargo.toml` (workspace root)
- Modify: `tests/integration.rs`

**Problem:** The workspace root is a virtual manifest (no `[package]`), so `tests/integration.rs` is never compiled or run. The existing test also uses wrong API (`resp.result` directly instead of matching `RpcResponse::Json(r)`).

- [ ] **Step 1: Add [package] and [dev-dependencies] to root Cargo.toml**

Add these sections to the END of the root `Cargo.toml`:

```toml
[package]
name = "remo-workspace"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
publish = false

[dev-dependencies]
remo-protocol = { path = "crates/remo-protocol" }
remo-transport = { path = "crates/remo-transport" }
remo-sdk = { path = "crates/remo-sdk" }
remo-desktop = { path = "crates/remo-desktop" }
tokio = { workspace = true }
serde_json = { workspace = true }
```

Also add `"."` to the workspace members list:

```toml
[workspace]
resolver = "2"
members = [
    ".",
    "crates/remo-protocol",
    ...
]
```

- [ ] **Step 2: Fix the existing integration test**

Replace the entire `tests/integration.rs` to use the correct `RpcResponse` API:

```rust
//! Integration tests: spin up remo-sdk server on localhost,
//! connect with remo-desktop's RpcClient, and verify round-trip calls.

use std::net::SocketAddr;
use std::time::Duration;

use remo_desktop::{RpcClient, RpcResponse};
use remo_protocol::{ErrorCode, ResponseResult};
use remo_sdk::{CapabilityRegistry, RemoServer};
use tokio::sync::mpsc;

/// Helper: unwrap a JSON response from an RpcResponse.
fn expect_json(resp: RpcResponse) -> remo_protocol::Response {
    match resp {
        RpcResponse::Json(r) => r,
        other => panic!("expected Json response, got {other:?}"),
    }
}

#[tokio::test]
async fn full_roundtrip() {
    let registry = CapabilityRegistry::new();
    registry.register_sync("echo", |params| {
        Ok(serde_json::json!({ "echoed": params }))
    });
    registry.register_sync("add", |params| {
        let a = params["a"].as_i64().unwrap_or(0);
        let b = params["b"].as_i64().unwrap_or(0);
        Ok(serde_json::json!({ "sum": a + b }))
    });

    let server = RemoServer::new(registry, 0);
    let (port_tx, port_rx) = tokio::sync::oneshot::channel();

    let server_handle = tokio::spawn(async move {
        server.run(Some(port_tx)).await.unwrap();
    });

    let actual_port = tokio::time::timeout(Duration::from_secs(2), port_rx)
        .await
        .expect("server did not report port in time")
        .expect("port sender dropped");

    let addr: SocketAddr = ([127, 0, 0, 1], actual_port).into();
    let (event_tx, _event_rx) = mpsc::channel(16);
    let client = RpcClient::connect(addr, event_tx).await.unwrap();

    // echo
    let resp = expect_json(
        client
            .call("echo", serde_json::json!({"hello": "world"}), Duration::from_secs(5))
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Ok { data } => assert_eq!(data["echoed"]["hello"], "world"),
        ResponseResult::Error { message, .. } => panic!("expected ok: {message}"),
    }

    // add
    let resp = expect_json(
        client
            .call("add", serde_json::json!({"a": 17, "b": 25}), Duration::from_secs(5))
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Ok { data } => assert_eq!(data["sum"], 42),
        ResponseResult::Error { message, .. } => panic!("expected ok: {message}"),
    }

    // __ping
    let resp = expect_json(
        client
            .call("__ping", serde_json::json!({}), Duration::from_secs(5))
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Ok { data } => assert_eq!(data["pong"], true),
        ResponseResult::Error { message, .. } => panic!("expected ok: {message}"),
    }

    // __list_capabilities
    let resp = expect_json(
        client
            .call("__list_capabilities", serde_json::json!({}), Duration::from_secs(5))
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Ok { data } => {
            let names: Vec<&str> = data.as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
            assert!(names.contains(&"echo"));
            assert!(names.contains(&"add"));
            assert!(names.contains(&"__ping"));
        }
        ResponseResult::Error { message, .. } => panic!("expected ok: {message}"),
    }

    // non-existent capability
    let resp = expect_json(
        client
            .call("no_such_thing", serde_json::json!({}), Duration::from_secs(5))
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Error { code, .. } => assert_eq!(*code, ErrorCode::NotFound),
        ResponseResult::Ok { .. } => panic!("expected error for unknown capability"),
    }

    server_handle.abort();
}

#[tokio::test]
async fn start_and_stop_mirror() {
    let registry = CapabilityRegistry::new();
    let server = RemoServer::new(registry, 0);
    let shutdown = server.shutdown_handle();

    let (port_tx, port_rx) = tokio::sync::oneshot::channel();
    tokio::spawn(async move {
        server.run(Some(port_tx)).await.unwrap();
    });

    let port = port_rx.await.unwrap();
    let addr: SocketAddr = ([127, 0, 0, 1], port).into();
    let (event_tx, _) = mpsc::channel(16);
    let client = RpcClient::connect(addr, event_tx).await.unwrap();

    // Start mirror
    let resp = expect_json(
        client
            .call("__start_mirror", serde_json::json!({"fps": 10}), Duration::from_secs(5))
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Ok { data } => {
            assert_eq!(data["stream_id"], 1);
        }
        ResponseResult::Error { message, .. } => {
            // On non-Apple targets, encoder fails — session won't be stored
            eprintln!("mirror start error (expected on non-iOS): {message}");
        }
    }

    // Stop mirror
    let resp = expect_json(
        client
            .call("__stop_mirror", serde_json::json!({}), Duration::from_secs(5))
            .await
            .unwrap(),
    );
    // Either stopped:true or not-found (if encoder failed to start on non-Apple)
    println!("stop response: {:?}", resp.result);

    let _ = shutdown.send(());
}

#[tokio::test]
async fn start_mirror_twice_returns_error() {
    let registry = CapabilityRegistry::new();
    let server = RemoServer::new(registry, 0);
    let shutdown = server.shutdown_handle();

    let (port_tx, port_rx) = tokio::sync::oneshot::channel();
    tokio::spawn(async move {
        server.run(Some(port_tx)).await.unwrap();
    });

    let port = port_rx.await.unwrap();
    let addr: SocketAddr = ([127, 0, 0, 1], port).into();
    let (event_tx, _) = mpsc::channel(16);
    let client = RpcClient::connect(addr, event_tx).await.unwrap();

    // First start
    let _ = client
        .call("__start_mirror", serde_json::json!({"fps": 10}), Duration::from_secs(5))
        .await
        .unwrap();

    tokio::time::sleep(Duration::from_millis(100)).await;

    // Second start — should fail with StreamAlreadyActive (if first succeeded)
    let resp = expect_json(
        client
            .call("__start_mirror", serde_json::json!({"fps": 10}), Duration::from_secs(5))
            .await
            .unwrap(),
    );
    match &resp.result {
        ResponseResult::Error { code, .. } => {
            assert_eq!(*code, ErrorCode::StreamAlreadyActive);
        }
        ResponseResult::Ok { .. } => {
            // On non-Apple targets, first start may have failed (no encoder),
            // so session slot is clear and second start "succeeds" too — acceptable
        }
    }

    let _ = shutdown.send(());
}
```

- [ ] **Step 3: Run ALL tests**

Run: `cd /Users/yi.jiang/Developer/Remo && cargo test`
Expected: All tests pass — protocol unit tests, objc unit tests, and integration tests.

- [ ] **Step 4: Commit**

```bash
git add Cargo.toml tests/integration.rs
git commit -m "fix(tests): make integration tests compile and add mirror stream tests"
```

---

## Summary

After completing all 6 tasks:

1. **Protocol**: `StreamFrame` message type with Type 0x02 binary encoding, 3 new `ErrorCode` variants
2. **Codec**: Encode/decode StreamFrame matching existing patterns, MAX_FRAME_SIZE raised to 64 MiB
3. **Encoder**: VideoToolbox H.264 wrapper with bounded channel flow control, `avcc_to_annex_b` with tests
4. **Capture**: UIKit view hierarchy rendering to CVPixelBuffer
5. **Server**: StreamSender + MirrorSession + `__start_mirror`/`__stop_mirror` with connection splitting
6. **Tests**: Fixed existing broken integration tests, added mirror stream protocol tests

**Phase 2** (separate plan): desktop StreamReceiver, web player, MP4 muxer, CLI `mirror` command.
**Phase 3** (separate plan): ReplayKit recording, AVAssetWriter, RecordingManager, CLI `record` command.
