use bytes::{Buf, BufMut, BytesMut};
use tokio_util::codec::{Decoder, Encoder};

use crate::message::{Message, MessageId};

/// Length-prefixed codec with a type byte discriminator.
///
/// Wire format:
/// ```text
/// ┌──────────┬──────────┬─────────────────────────────────────┐
/// │ len (4B) │ type(1B) │           payload                   │
/// │ u32 BE   │          │           (len - 1 bytes)           │
/// └──────────┴──────────┴─────────────────────────────────────┘
///
/// type 0x00: payload = JSON bytes
/// type 0x01: payload = meta_len(4B BE) + JSON metadata(meta_len bytes) + raw binary(rest)
/// ```
///
/// `len` INCLUDES the type byte. Total wire bytes = 4 (length prefix) + len.
#[derive(Debug, Default, Clone)]
pub struct RemoCodec;

/// Maximum message size: 16 MiB. Anything larger is rejected.
const MAX_FRAME_SIZE: u32 = 16 * 1024 * 1024;

const FRAME_TYPE_JSON: u8 = 0x00;
const FRAME_TYPE_BINARY: u8 = 0x01;

#[derive(Debug, thiserror::Error)]
pub enum CodecError {
    #[error("frame too large: {0} bytes (max {MAX_FRAME_SIZE})")]
    FrameTooLarge(u32),

    #[error("unknown frame type: 0x{0:02x}")]
    UnknownFrameType(u8),

    #[error("malformed binary frame: {0}")]
    MalformedBinaryFrame(String),

    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}

impl Decoder for RemoCodec {
    type Item = Message;
    type Error = CodecError;

    fn decode(&mut self, src: &mut BytesMut) -> Result<Option<Self::Item>, Self::Error> {
        if src.len() < 4 {
            return Ok(None);
        }

        let len = u32::from_be_bytes([src[0], src[1], src[2], src[3]]);

        if len > MAX_FRAME_SIZE {
            return Err(CodecError::FrameTooLarge(len));
        }

        let total = 4 + len as usize;
        if src.len() < total {
            src.reserve(total - src.len());
            return Ok(None);
        }

        // Consume length prefix
        src.advance(4);

        let payload_len = len as usize;
        if payload_len == 0 {
            return Err(CodecError::MalformedBinaryFrame("empty frame".into()));
        }

        let frame_type = src[0];
        src.advance(1);
        let body_len = payload_len - 1;

        match frame_type {
            FRAME_TYPE_JSON => {
                let body = src.split_to(body_len);
                let msg: Message = serde_json::from_slice(&body)?;
                Ok(Some(msg))
            }
            FRAME_TYPE_BINARY => {
                if body_len < 4 {
                    return Err(CodecError::MalformedBinaryFrame(
                        "binary frame too short for meta_len header".into(),
                    ));
                }
                let meta_len = u32::from_be_bytes([src[0], src[1], src[2], src[3]]) as usize;
                src.advance(4);

                if meta_len + 4 > body_len {
                    return Err(CodecError::MalformedBinaryFrame(format!(
                        "meta_len ({meta_len}) exceeds frame body ({body_len})"
                    )));
                }

                let meta_bytes = src.split_to(meta_len);
                let meta_wrapper: serde_json::Value = serde_json::from_slice(&meta_bytes)?;

                let data_len = body_len - 4 - meta_len;
                let data = src.split_to(data_len).to_vec();

                let id: MessageId =
                    serde_json::from_value(meta_wrapper.get("id").cloned().unwrap_or_default())
                        .unwrap_or_else(|_| uuid::Uuid::new_v4());
                let metadata = meta_wrapper.get("metadata").cloned().unwrap_or_default();

                Ok(Some(Message::BinaryResponse(
                    crate::message::BinaryResponse::new(id, metadata, data),
                )))
            }
            other => Err(CodecError::UnknownFrameType(other)),
        }
    }
}

impl Encoder<Message> for RemoCodec {
    type Error = CodecError;

    fn encode(&mut self, item: Message, dst: &mut BytesMut) -> Result<(), Self::Error> {
        match item {
            Message::BinaryResponse(br) => {
                let meta_json = serde_json::to_vec(&serde_json::json!({
                    "id": br.id,
                    "metadata": br.metadata,
                }))?;
                let meta_len = meta_json.len() as u32;
                // len = 1 (type) + 4 (meta_len) + meta_json.len() + data.len()
                let payload_len = 1 + 4 + meta_json.len() + br.data.len();
                let frame_len = payload_len as u32;

                if frame_len > MAX_FRAME_SIZE {
                    return Err(CodecError::FrameTooLarge(frame_len));
                }

                dst.reserve(4 + payload_len);
                dst.put_u32(frame_len);
                dst.put_u8(FRAME_TYPE_BINARY);
                dst.put_u32(meta_len);
                dst.extend_from_slice(&meta_json);
                dst.extend_from_slice(&br.data);
                Ok(())
            }
            _ => {
                let json = serde_json::to_vec(&item)?;
                let payload_len = 1 + json.len();
                let frame_len = payload_len as u32;

                if frame_len > MAX_FRAME_SIZE {
                    return Err(CodecError::FrameTooLarge(frame_len));
                }

                dst.reserve(4 + payload_len);
                dst.put_u32(frame_len);
                dst.put_u8(FRAME_TYPE_JSON);
                dst.extend_from_slice(&json);
                Ok(())
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::message::Request;

    #[test]
    fn roundtrip_encode_decode() {
        let mut codec = RemoCodec;
        let mut buf = BytesMut::new();

        let req = Message::Request(Request::new(
            "navigate",
            serde_json::json!({"route": "/home"}),
        ));

        codec.encode(req.clone(), &mut buf).unwrap();

        let decoded = codec.decode(&mut buf).unwrap().expect("should decode");

        // Verify the capability matches.
        match decoded {
            Message::Request(r) => {
                assert_eq!(r.capability, "navigate");
                assert_eq!(r.params["route"], "/home");
            }
            other => panic!("expected Request, got {:?}", other),
        }

        // Buffer should be fully consumed.
        assert!(buf.is_empty());
    }

    #[test]
    fn partial_read() {
        let mut codec = RemoCodec;
        let mut buf = BytesMut::new();

        let req = Message::Request(Request::new("ping", serde_json::json!({})));
        codec.encode(req, &mut buf).unwrap();

        // Split in the middle — simulate partial TCP read.
        let mut partial = buf.split_to(buf.len() / 2);
        assert!(codec.decode(&mut partial).unwrap().is_none());

        // Append the rest.
        partial.extend_from_slice(&buf);
        assert!(codec.decode(&mut partial).unwrap().is_some());
    }

    #[test]
    fn rejects_oversized_frame() {
        let mut codec = RemoCodec;
        let mut buf = BytesMut::new();
        // Write a length header claiming 20 MiB.
        buf.put_u32(20 * 1024 * 1024);
        buf.extend_from_slice(b"{}");

        assert!(codec.decode(&mut buf).is_err());
    }

    #[test]
    fn roundtrip_binary_response() {
        let mut codec = RemoCodec;
        let mut buf = BytesMut::new();

        let br = Message::BinaryResponse(crate::message::BinaryResponse::new(
            uuid::Uuid::new_v4(),
            serde_json::json!({"format": "jpeg", "width": 393.0}),
            vec![0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3],
        ));

        codec.encode(br.clone(), &mut buf).unwrap();

        assert_eq!(buf[4], 0x01);

        let decoded = codec.decode(&mut buf).unwrap().expect("should decode");
        match decoded {
            Message::BinaryResponse(r) => {
                assert_eq!(r.metadata["format"], "jpeg");
                assert_eq!(r.data, vec![0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
            }
            other => panic!("expected BinaryResponse, got {:?}", other),
        }
        assert!(buf.is_empty());
    }

    #[test]
    fn json_frames_still_work_with_type_byte() {
        let mut codec = RemoCodec;
        let mut buf = BytesMut::new();

        let req = Message::Request(Request::new("ping", serde_json::json!({})));
        codec.encode(req, &mut buf).unwrap();

        assert_eq!(buf[4], 0x00);

        let decoded = codec.decode(&mut buf).unwrap().expect("should decode");
        match decoded {
            Message::Request(r) => assert_eq!(r.capability, "ping"),
            other => panic!("expected Request, got {:?}", other),
        }
    }

    #[test]
    fn binary_frame_partial_read() {
        let mut codec = RemoCodec;
        let mut buf = BytesMut::new();

        let br = Message::BinaryResponse(crate::message::BinaryResponse::new(
            uuid::Uuid::new_v4(),
            serde_json::json!({"format": "png"}),
            vec![0x89, 0x50, 0x4E, 0x47],
        ));

        codec.encode(br, &mut buf).unwrap();
        let mut partial = buf.split_to(buf.len() / 2);
        assert!(codec.decode(&mut partial).unwrap().is_none());
        partial.extend_from_slice(&buf);
        assert!(codec.decode(&mut partial).unwrap().is_some());
    }
}
