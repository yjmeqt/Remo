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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    /// Event kind (e.g. "state_changed", "navigation", "log").
    pub kind: String,
    #[serde(default)]
    pub payload: serde_json::Value,
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
