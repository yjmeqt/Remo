use bytes::{Buf, BufMut, BytesMut};
use tokio_util::codec::{Decoder, Encoder};

use crate::message::Message;

/// 4-byte big-endian length prefix + JSON body.
///
/// Wire format:
/// ```text
/// ┌──────────┬─────────────────────┐
/// │ len (4B) │   JSON payload      │
/// │ u32 BE   │   `len` bytes       │
/// └──────────┴─────────────────────┘
/// ```
#[derive(Debug, Default, Clone)]
pub struct RemoCodec;

/// Maximum message size: 16 MiB. Anything larger is rejected.
const MAX_FRAME_SIZE: u32 = 16 * 1024 * 1024;

#[derive(Debug, thiserror::Error)]
pub enum CodecError {
    #[error("frame too large: {0} bytes (max {MAX_FRAME_SIZE})")]
    FrameTooLarge(u32),

    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}

impl Decoder for RemoCodec {
    type Item = Message;
    type Error = CodecError;

    fn decode(&mut self, src: &mut BytesMut) -> Result<Option<Self::Item>, Self::Error> {
        // Need at least 4 bytes for the length prefix.
        if src.len() < 4 {
            return Ok(None);
        }

        // Peek at the length without consuming.
        let len = u32::from_be_bytes([src[0], src[1], src[2], src[3]]);

        if len > MAX_FRAME_SIZE {
            return Err(CodecError::FrameTooLarge(len));
        }

        let total = 4 + len as usize;
        if src.len() < total {
            // Reserve space to avoid repeated allocations.
            src.reserve(total - src.len());
            return Ok(None);
        }

        // Consume the length prefix.
        src.advance(4);
        // Consume the JSON body.
        let body = src.split_to(len as usize);

        let msg: Message = serde_json::from_slice(&body)?;
        Ok(Some(msg))
    }
}

impl Encoder<Message> for RemoCodec {
    type Error = CodecError;

    fn encode(&mut self, item: Message, dst: &mut BytesMut) -> Result<(), Self::Error> {
        let json = serde_json::to_vec(&item)?;
        let len = json.len() as u32;

        if len > MAX_FRAME_SIZE {
            return Err(CodecError::FrameTooLarge(len));
        }

        dst.reserve(4 + json.len());
        dst.put_u32(len);
        dst.extend_from_slice(&json);
        Ok(())
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
}
