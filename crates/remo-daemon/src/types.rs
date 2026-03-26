use chrono::{DateTime, Utc};
use remo_desktop::DeviceId;
use serde::{Deserialize, Serialize};

/// Unified daemon event with sequence number for cursor-based polling.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonEvent {
    pub seq: u64,
    pub timestamp: DateTime<Utc>,
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device: Option<String>,
    pub payload: serde_json::Value,
}

/// Device connection state as tracked by the daemon.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DeviceState {
    Discovered,
    Connecting,
    Connected,
    Disconnected,
}

/// Call mode for /call endpoint.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CallMode {
    #[default]
    Await,
    Fire,
}

/// Daemon metadata written to ~/.remo/daemon.json.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonInfo {
    pub pid: u32,
    pub port: u16,
    pub started_at: DateTime<Utc>,
}

/// Webhook registration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Webhook {
    pub id: String,
    pub url: String,
    #[serde(default)]
    pub filter: Vec<String>,
}

/// Format a DeviceId as a string for event payloads.
pub fn device_id_to_string(id: &DeviceId) -> String {
    match id {
        DeviceId::Usb(n) => format!("usb:{}", n),
        DeviceId::Bonjour(name) => format!("bonjour:{}", name),
    }
}

/// Parse a device ID string back into a DeviceId.
pub fn parse_device_id(s: &str) -> Option<DeviceId> {
    if let Some(n) = s.strip_prefix("usb:") {
        n.parse().ok().map(DeviceId::Usb)
    } else {
        s.strip_prefix("bonjour:")
            .map(|name| DeviceId::Bonjour(name.to_string()))
    }
}
