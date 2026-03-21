use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DeviceInfo {
    pub device_id: u32,
    pub serial_number: String,
    pub product_id: u16,
    pub connection_type: ConnectionType,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ConnectionType {
    Usb,
    Simulator,
    Network,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CapabilityInfo {
    pub name: String,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ViewNode {
    pub class_name: String,
    pub address: String,
    pub frame: Rect,
    pub properties: serde_json::Map<String, serde_json::Value>,
    pub children: Vec<ViewNode>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StoreEntry {
    pub key: String,
    pub value: serde_json::Value,
    pub value_type: String,
}

impl ViewNode {
    pub fn new(class_name: &str, address: &str, frame: Rect) -> Self {
        Self {
            class_name: class_name.to_string(),
            address: address.to_string(),
            frame,
            properties: serde_json::Map::new(),
            children: Vec::new(),
        }
    }
}
