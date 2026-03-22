use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Unique identifier for request-response pairing.
pub type MessageId = Uuid;

/// Top-level envelope sent over the wire.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Message {
    /// macOS → iOS: invoke a registered capability.
    #[serde(rename = "request")]
    Request(Request),

    /// iOS → macOS: result of a capability invocation.
    #[serde(rename = "response")]
    Response(Response),

    /// iOS → macOS: unsolicited push event.
    #[serde(rename = "event")]
    Event(Event),

    /// Binary response — not JSON-serialized; uses binary frame wire format.
    /// Serde skip: encoded/decoded manually by RemoCodec.
    #[serde(skip)]
    BinaryResponse(BinaryResponse),

    /// Stream frame — not JSON-serialized, uses Type 0x02 wire encoding.
    #[serde(skip)]
    StreamFrame(StreamFrame),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Request {
    pub id: MessageId,
    /// Name of the capability to invoke (e.g. "navigate", "state.get").
    pub capability: String,
    /// Arbitrary JSON parameters.
    #[serde(default)]
    pub params: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Response {
    /// Matches the `id` of the originating `Request`.
    pub id: MessageId,
    #[serde(flatten)]
    pub result: ResponseResult,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "status")]
pub enum ResponseResult {
    #[serde(rename = "ok")]
    Ok {
        #[serde(default)]
        data: serde_json::Value,
    },
    #[serde(rename = "error")]
    Error { code: ErrorCode, message: String },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    /// Capability not found in registry.
    NotFound,
    /// Parameters invalid for the capability.
    InvalidParams,
    /// Handler execution failed.
    Internal,
    /// Request timed out.
    Timeout,
    StreamAlreadyActive,
    AuthorizationDenied,
    RecordingNotFound,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    /// Event kind (e.g. "state_changed", "navigation", "log").
    pub kind: String,
    #[serde(default)]
    pub payload: serde_json::Value,
}

/// A response carrying binary payload (e.g. screenshot image bytes).
///
/// Not serialized as JSON — uses the binary frame wire format.
#[derive(Debug, Clone)]
pub struct BinaryResponse {
    /// Matches the `id` of the originating `Request`.
    pub id: MessageId,
    /// Small JSON metadata (format, dimensions, etc.).
    pub metadata: serde_json::Value,
    /// Raw binary payload (e.g. JPEG/PNG bytes).
    pub data: Vec<u8>,
}

// ---------------------------------------------------------------------------
// Convenience constructors
// ---------------------------------------------------------------------------

impl Request {
    pub fn new(capability: impl Into<String>, params: serde_json::Value) -> Self {
        Self {
            id: Uuid::new_v4(),
            capability: capability.into(),
            params,
        }
    }
}

impl Response {
    pub fn ok(id: MessageId, data: serde_json::Value) -> Self {
        Self {
            id,
            result: ResponseResult::Ok { data },
        }
    }

    pub fn error(id: MessageId, code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            id,
            result: ResponseResult::Error {
                code,
                message: message.into(),
            },
        }
    }
}

impl Event {
    pub fn new(kind: impl Into<String>, payload: serde_json::Value) -> Self {
        Self {
            kind: kind.into(),
            payload,
        }
    }
}

impl BinaryResponse {
    pub fn new(id: MessageId, metadata: serde_json::Value, data: Vec<u8>) -> Self {
        Self { id, metadata, data }
    }
}

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
