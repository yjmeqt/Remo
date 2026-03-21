use bytes::{Buf, BufMut, BytesMut};
use tokio_util::codec::{Decoder, Encoder};

const USBMUXD_VERSION: u32 = 1;
const USBMUXD_MSG_TYPE_PLIST: u32 = 8;
const USBMUXD_HEADER_SIZE: usize = 16;

/// Raw usbmuxd packet header (all fields little-endian u32).
///
/// ```text
/// ┌──────────┬──────────┬──────────┬──────────┐
/// │ length   │ version  │ type     │ tag      │
/// └──────────┴──────────┴──────────┴──────────┘
/// ```
///
/// `length` = header (16) + payload size.
#[derive(Debug, Clone)]
pub struct UsbmuxdPacket {
    pub tag: u32,
    pub payload: Vec<u8>,
}

impl UsbmuxdPacket {
    pub fn new(tag: u32, payload: Vec<u8>) -> Self {
        Self { tag, payload }
    }

    /// Build a plist request packet.
    pub fn plist_request(tag: u32, dict: &plist::Dictionary) -> Result<Self, plist::Error> {
        let val = plist::Value::Dictionary(dict.clone());
        let mut buf = Vec::new();
        val.to_writer_xml(&mut buf)?;
        Ok(Self::new(tag, buf))
    }

    /// Parse the payload as an XML plist dictionary.
    pub fn parse_plist(&self) -> Result<plist::Dictionary, String> {
        let val = plist::Value::from_reader(std::io::Cursor::new(&self.payload))
            .map_err(|e| format!("plist parse error: {e}"))?;
        val.into_dictionary()
            .ok_or_else(|| "expected plist dictionary".to_string())
    }
}

/// Builds a `ListDevices` plist request.
pub fn build_list_devices(tag: u32) -> UsbmuxdPacket {
    let mut dict = plist::Dictionary::new();
    dict.insert("MessageType".into(), "ListDevices".into());
    dict.insert("ClientVersionString".into(), "remo-0.1.0".into());
    dict.insert("ProgName".into(), "remo".into());
    UsbmuxdPacket::plist_request(tag, &dict).expect("plist serialization cannot fail")
}

/// Builds a `Listen` plist request (subscribe to attach/detach events).
pub fn build_listen(tag: u32) -> UsbmuxdPacket {
    let mut dict = plist::Dictionary::new();
    dict.insert("MessageType".into(), "Listen".into());
    dict.insert("ClientVersionString".into(), "remo-0.1.0".into());
    dict.insert("ProgName".into(), "remo".into());
    UsbmuxdPacket::plist_request(tag, &dict).expect("plist serialization cannot fail")
}

/// Builds a `Connect` plist request.
///
/// `port` is in **host byte order**; the function converts it to
/// network byte order (big-endian) as required by usbmuxd.
pub fn build_connect(tag: u32, device_id: u32, port: u16) -> UsbmuxdPacket {
    let mut dict = plist::Dictionary::new();
    dict.insert("MessageType".into(), "Connect".into());
    dict.insert("DeviceID".into(), plist::Value::Integer(device_id.into()));
    let network_port = port.to_be() as u64;
    dict.insert("PortNumber".into(), plist::Value::Integer(network_port.into()));
    dict.insert("ClientVersionString".into(), "remo-0.1.0".into());
    dict.insert("ProgName".into(), "remo".into());
    UsbmuxdPacket::plist_request(tag, &dict).expect("plist serialization cannot fail")
}

// --- Codec ---

pub struct UsbmuxdCodec;

impl Decoder for UsbmuxdCodec {
    type Item = UsbmuxdPacket;
    type Error = std::io::Error;

    fn decode(&mut self, src: &mut BytesMut) -> Result<Option<UsbmuxdPacket>, Self::Error> {
        if src.len() < USBMUXD_HEADER_SIZE {
            return Ok(None);
        }

        let length = u32::from_le_bytes([src[0], src[1], src[2], src[3]]) as usize;
        if length < USBMUXD_HEADER_SIZE {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "usbmuxd packet too small",
            ));
        }

        if src.len() < length {
            src.reserve(length - src.len());
            return Ok(None);
        }

        src.advance(4); // length
        let _version = src.get_u32_le();
        let _msg_type = src.get_u32_le();
        let tag = src.get_u32_le();

        let payload_len = length - USBMUXD_HEADER_SIZE;
        let payload = src.split_to(payload_len).to_vec();

        Ok(Some(UsbmuxdPacket { tag, payload }))
    }
}

impl Encoder<UsbmuxdPacket> for UsbmuxdCodec {
    type Error = std::io::Error;

    fn encode(&mut self, pkt: UsbmuxdPacket, dst: &mut BytesMut) -> Result<(), Self::Error> {
        let length = (USBMUXD_HEADER_SIZE + pkt.payload.len()) as u32;
        dst.reserve(length as usize);
        dst.put_u32_le(length);
        dst.put_u32_le(USBMUXD_VERSION);
        dst.put_u32_le(USBMUXD_MSG_TYPE_PLIST);
        dst.put_u32_le(pkt.tag);
        dst.extend_from_slice(&pkt.payload);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_usbmuxd_codec_roundtrip() {
        let pkt = build_list_devices(1);
        let mut codec = UsbmuxdCodec;

        let mut buf = BytesMut::new();
        codec.encode(pkt.clone(), &mut buf).unwrap();

        let decoded = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(decoded.tag, 1);

        let dict = decoded.parse_plist().unwrap();
        assert_eq!(
            dict.get("MessageType").and_then(|v| v.as_string()),
            Some("ListDevices")
        );
    }

    #[test]
    fn test_connect_port_byte_order() {
        let pkt = build_connect(2, 100, 9876);
        let dict = pkt.parse_plist().unwrap();
        let port_val = dict
            .get("PortNumber")
            .and_then(|v| v.as_unsigned_integer())
            .unwrap();
        assert_eq!(port_val, 9876_u16.to_be() as u64);
    }

    #[test]
    fn test_listen_request() {
        let pkt = build_listen(3);
        let dict = pkt.parse_plist().unwrap();
        assert_eq!(
            dict.get("MessageType").and_then(|v| v.as_string()),
            Some("Listen")
        );
    }

    #[test]
    fn test_usbmuxd_codec_partial() {
        let pkt = build_list_devices(5);
        let mut codec = UsbmuxdCodec;

        let mut full = BytesMut::new();
        codec.encode(pkt, &mut full).unwrap();

        let mut partial = BytesMut::new();
        partial.extend_from_slice(&full[..8]);
        assert!(codec.decode(&mut partial).unwrap().is_none());

        partial.extend_from_slice(&full[8..]);
        let decoded = codec.decode(&mut partial).unwrap().unwrap();
        assert_eq!(decoded.tag, 5);
    }
}
