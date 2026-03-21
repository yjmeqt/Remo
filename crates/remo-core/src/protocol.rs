use bytes::{Buf, BufMut, BytesMut};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio_util::codec::{Decoder, Encoder};

pub const HANDSHAKE_MAGIC: [u8; 4] = *b"REMO";
pub const PROTOCOL_VERSION: u32 = 1;

const MSG_TYPE_REQUEST: u8 = 0x01;
const MSG_TYPE_RESPONSE: u8 = 0x02;
const MSG_TYPE_EVENT: u8 = 0x03;

const MAX_FRAME_SIZE: usize = 16 * 1024 * 1024; // 16 MB

// --- Wire messages ---

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Request {
    pub capability: String,
    pub params: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Response {
    pub success: bool,
    pub data: serde_json::Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Event {
    pub name: String,
    pub data: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Message {
    Request { id: u32, body: Request },
    Response { id: u32, body: Response },
    Event { id: u32, body: Event },
}

impl Message {
    pub fn id(&self) -> u32 {
        match self {
            Message::Request { id, .. } => *id,
            Message::Response { id, .. } => *id,
            Message::Event { id, .. } => *id,
        }
    }

    pub fn request(id: u32, capability: &str, params: serde_json::Value) -> Self {
        Message::Request {
            id,
            body: Request {
                capability: capability.to_string(),
                params,
            },
        }
    }

    pub fn response_ok(id: u32, data: serde_json::Value) -> Self {
        Message::Response {
            id,
            body: Response {
                success: true,
                data,
                error: None,
            },
        }
    }

    pub fn response_err(id: u32, error: String) -> Self {
        Message::Response {
            id,
            body: Response {
                success: false,
                data: serde_json::Value::Null,
                error: Some(error),
            },
        }
    }

    pub fn event(id: u32, name: &str, data: serde_json::Value) -> Self {
        Message::Event {
            id,
            body: Event {
                name: name.to_string(),
                data,
            },
        }
    }
}

// --- Frame codec ---
//
// Wire format (little-endian):
//   [payload_len: u32][msg_id: u32][msg_type: u8][payload: bytes]
//
// payload_len = sizeof(msg_id) + sizeof(msg_type) + sizeof(payload)
//             = 4 + 1 + payload.len()

pub struct RemoCodec;

impl Decoder for RemoCodec {
    type Item = Message;
    type Error = std::io::Error;

    fn decode(&mut self, src: &mut BytesMut) -> Result<Option<Message>, Self::Error> {
        if src.len() < 4 {
            return Ok(None);
        }

        let frame_len =
            u32::from_le_bytes([src[0], src[1], src[2], src[3]]) as usize;

        if frame_len < 5 {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "frame too small",
            ));
        }
        if frame_len > MAX_FRAME_SIZE {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("frame too large: {frame_len}"),
            ));
        }

        if src.len() < 4 + frame_len {
            src.reserve(4 + frame_len - src.len());
            return Ok(None);
        }

        src.advance(4); // consume length prefix
        let msg_id = src.get_u32_le();
        let msg_type = src.get_u8();
        let payload_len = frame_len - 5;
        let payload = src.split_to(payload_len);

        let message = match msg_type {
            MSG_TYPE_REQUEST => {
                let body: Request = rmp_serde::from_slice(&payload).map_err(|e| {
                    std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string())
                })?;
                Message::Request { id: msg_id, body }
            }
            MSG_TYPE_RESPONSE => {
                let body: Response = rmp_serde::from_slice(&payload).map_err(|e| {
                    std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string())
                })?;
                Message::Response { id: msg_id, body }
            }
            MSG_TYPE_EVENT => {
                let body: Event = rmp_serde::from_slice(&payload).map_err(|e| {
                    std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string())
                })?;
                Message::Event { id: msg_id, body }
            }
            other => {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    format!("unknown message type: 0x{other:02x}"),
                ));
            }
        };

        Ok(Some(message))
    }
}

impl Encoder<Message> for RemoCodec {
    type Error = std::io::Error;

    fn encode(&mut self, msg: Message, dst: &mut BytesMut) -> Result<(), Self::Error> {
        let (msg_id, msg_type, payload) = match &msg {
            Message::Request { id, body } => {
                let p = rmp_serde::to_vec_named(body).map_err(|e| {
                    std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string())
                })?;
                (*id, MSG_TYPE_REQUEST, p)
            }
            Message::Response { id, body } => {
                let p = rmp_serde::to_vec_named(body).map_err(|e| {
                    std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string())
                })?;
                (*id, MSG_TYPE_RESPONSE, p)
            }
            Message::Event { id, body } => {
                let p = rmp_serde::to_vec_named(body).map_err(|e| {
                    std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string())
                })?;
                (*id, MSG_TYPE_EVENT, p)
            }
        };

        let frame_len = 4 + 1 + payload.len();
        dst.reserve(4 + frame_len);
        dst.put_u32_le(frame_len as u32);
        dst.put_u32_le(msg_id);
        dst.put_u8(msg_type);
        dst.extend_from_slice(&payload);
        Ok(())
    }
}

// --- Handshake ---

pub async fn write_handshake(writer: &mut (impl AsyncWrite + Unpin)) -> std::io::Result<()> {
    writer.write_all(&HANDSHAKE_MAGIC).await?;
    writer.write_all(&PROTOCOL_VERSION.to_le_bytes()).await?;
    writer.flush().await?;
    Ok(())
}

pub async fn read_handshake(reader: &mut (impl AsyncRead + Unpin)) -> Result<u32, crate::RemoError> {
    let mut magic = [0u8; 4];
    reader.read_exact(&mut magic).await?;
    if magic != HANDSHAKE_MAGIC {
        return Err(crate::RemoError::HandshakeFailed(format!(
            "invalid magic: {:?}",
            magic
        )));
    }
    let mut version_bytes = [0u8; 4];
    reader.read_exact(&mut version_bytes).await?;
    Ok(u32::from_le_bytes(version_bytes))
}

// --- Tests ---

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_codec_request_roundtrip() {
        let mut codec = RemoCodec;
        let msg = Message::request(42, "echo", serde_json::json!({"hello": "world"}));

        let mut buf = BytesMut::new();
        codec.encode(msg.clone(), &mut buf).unwrap();

        let decoded = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(decoded, msg);
    }

    #[test]
    fn test_codec_response_roundtrip() {
        let mut codec = RemoCodec;
        let msg = Message::response_ok(1, serde_json::json!({"result": 42}));

        let mut buf = BytesMut::new();
        codec.encode(msg.clone(), &mut buf).unwrap();

        let decoded = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(decoded, msg);
    }

    #[test]
    fn test_codec_error_response_roundtrip() {
        let mut codec = RemoCodec;
        let msg = Message::response_err(5, "not found".to_string());

        let mut buf = BytesMut::new();
        codec.encode(msg.clone(), &mut buf).unwrap();

        let decoded = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(decoded, msg);
    }

    #[test]
    fn test_codec_event_roundtrip() {
        let mut codec = RemoCodec;
        let msg = Message::event(0, "state_changed", serde_json::json!({"page": "home"}));

        let mut buf = BytesMut::new();
        codec.encode(msg.clone(), &mut buf).unwrap();

        let decoded = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(decoded, msg);
    }

    #[test]
    fn test_codec_partial_read() {
        let mut codec = RemoCodec;
        let msg = Message::request(1, "test", serde_json::json!(null));

        let mut full = BytesMut::new();
        codec.encode(msg.clone(), &mut full).unwrap();

        // Feed bytes one at a time
        let mut partial = BytesMut::new();
        for i in 0..full.len() - 1 {
            partial.extend_from_slice(&full[i..i + 1]);
            assert!(codec.decode(&mut partial).unwrap().is_none());
        }
        // Feed last byte
        partial.extend_from_slice(&full[full.len() - 1..]);
        let decoded = codec.decode(&mut partial).unwrap().unwrap();
        assert_eq!(decoded, msg);
    }

    #[test]
    fn test_codec_multiple_messages() {
        let mut codec = RemoCodec;
        let msgs = vec![
            Message::request(1, "a", serde_json::json!(1)),
            Message::response_ok(1, serde_json::json!(2)),
            Message::event(0, "b", serde_json::json!(3)),
        ];

        let mut buf = BytesMut::new();
        for m in &msgs {
            codec.encode(m.clone(), &mut buf).unwrap();
        }

        for expected in &msgs {
            let decoded = codec.decode(&mut buf).unwrap().unwrap();
            assert_eq!(&decoded, expected);
        }
        assert!(codec.decode(&mut buf).unwrap().is_none());
    }

    #[tokio::test]
    async fn test_handshake_roundtrip() {
        let mut buf = Vec::new();
        write_handshake(&mut buf).await.unwrap();
        assert_eq!(buf.len(), 8);

        let mut cursor = std::io::Cursor::new(buf);
        let version = read_handshake(&mut cursor).await.unwrap();
        assert_eq!(version, PROTOCOL_VERSION);
    }

    #[tokio::test]
    async fn test_handshake_invalid_magic() {
        let buf = vec![0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00];
        let mut cursor = std::io::Cursor::new(buf);
        let result = read_handshake(&mut cursor).await;
        assert!(result.is_err());
    }
}
