use serde::{Deserialize, Serialize};

/// Header for usbmuxd binary protocol.
/// Each message is: 16-byte header + payload.
#[derive(Debug, Clone, Copy)]
#[repr(C)]
pub struct UsbmuxHeader {
    /// Total length including this header.
    pub length: u32,
    /// Protocol version (always 1 for plist protocol).
    pub version: u32,
    /// Message type.
    pub msg_type: u32,
    /// Tag for request-response matching.
    pub tag: u32,
}

/// usbmuxd message types.
pub const MSG_TYPE_RESULT: u32 = 1;
pub const MSG_TYPE_CONNECT: u32 = 2;
pub const MSG_TYPE_LISTEN: u32 = 3;
pub const MSG_TYPE_PLIST: u32 = 8;

/// usbmuxd plist protocol version.
pub const USBMUX_VERSION: u32 = 1;

/// Plist request sent to usbmuxd.
#[derive(Debug, Clone, Serialize)]
pub struct UsbmuxRequest {
    #[serde(rename = "MessageType")]
    pub message_type: String,

    #[serde(rename = "ProgName")]
    pub prog_name: String,

    #[serde(rename = "ClientVersionString")]
    pub client_version: String,

    /// Only for Connect requests.
    #[serde(rename = "DeviceID", skip_serializing_if = "Option::is_none")]
    pub device_id: Option<u32>,

    /// Only for Connect requests — the port on the device (network byte order).
    #[serde(rename = "PortNumber", skip_serializing_if = "Option::is_none")]
    pub port_number: Option<u16>,
}

/// Plist response from usbmuxd.
#[derive(Debug, Clone, Deserialize)]
pub struct UsbmuxResponse {
    #[serde(rename = "MessageType")]
    pub message_type: String,

    #[serde(rename = "Number", default)]
    pub number: Option<i64>,
}

/// Device attached event from usbmuxd.
#[derive(Debug, Clone, Deserialize)]
pub struct DeviceAttached {
    #[serde(rename = "DeviceID")]
    pub device_id: u32,

    #[serde(rename = "Properties")]
    pub properties: DeviceProperties,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DeviceProperties {
    #[serde(rename = "ConnectionType")]
    pub connection_type: String,

    #[serde(rename = "DeviceID")]
    pub device_id: u32,

    #[serde(rename = "SerialNumber")]
    pub serial_number: String,

    #[serde(rename = "UDID", default)]
    pub udid: Option<String>,

    #[serde(rename = "ProductID", default)]
    pub product_id: Option<u32>,
}

/// Represents a discovered iOS device.
#[derive(Debug, Clone)]
pub struct Device {
    pub device_id: u32,
    pub serial: String,
    pub udid: Option<String>,
    pub connection_type: String,
}

impl From<DeviceAttached> for Device {
    fn from(evt: DeviceAttached) -> Self {
        Self {
            device_id: evt.device_id,
            serial: evt.properties.serial_number,
            udid: evt.properties.udid,
            connection_type: evt.properties.connection_type,
        }
    }
}
