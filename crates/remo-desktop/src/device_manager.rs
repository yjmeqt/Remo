use std::fmt;
use std::net::SocketAddr;
use std::sync::Arc;

use dashmap::DashMap;
use remo_bonjour::{BrowseEvent, ServiceBrowser};
use remo_transport::Connection;
use remo_usbmuxd::{Device, DeviceEvent, UsbmuxClient};
use tokio::sync::mpsc;
use tracing::info;

use crate::rpc_client::RpcClient;

const DEFAULT_DEVICE_PORT: u16 = remo_protocol::DEFAULT_PORT;

// ---------------------------------------------------------------------------
// Unified device model
// ---------------------------------------------------------------------------

/// Unique key for a discovered device.
#[derive(Debug, Clone, Hash, Eq, PartialEq)]
pub enum DeviceId {
    Usb(u32),
    Bonjour(String),
}

impl fmt::Display for DeviceId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DeviceId::Usb(id) => write!(f, "usb:{id}"),
            DeviceId::Bonjour(name) => write!(f, "bonjour:{name}"),
        }
    }
}

/// Transport-agnostic device information.
#[derive(Debug, Clone)]
pub struct DeviceInfo {
    pub id: DeviceId,
    pub display_name: String,
    pub transport: DeviceTransport,
}

#[derive(Debug, Clone)]
pub enum DeviceTransport {
    Usb { device: Device },
    Bonjour { host: String, port: u16 },
    Manual { addr: SocketAddr },
}

impl DeviceInfo {
    pub fn addr(&self) -> Option<SocketAddr> {
        match &self.transport {
            DeviceTransport::Bonjour { host, port } => {
                use std::net::ToSocketAddrs;
                format!("{}:{}", host.trim_end_matches('.'), port)
                    .to_socket_addrs()
                    .ok()?
                    .next()
            }
            DeviceTransport::Manual { addr } => Some(*addr),
            DeviceTransport::Usb { .. } => None,
        }
    }
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub enum DeviceManagerEvent {
    DeviceAdded(DeviceInfo),
    DeviceRemoved(DeviceId),
}

// ---------------------------------------------------------------------------
// DeviceManager
// ---------------------------------------------------------------------------

/// Manages discovered iOS devices and their RPC connections.
pub struct DeviceManager {
    devices: Arc<DashMap<DeviceId, DeviceInfo>>,
    event_tx: mpsc::Sender<DeviceManagerEvent>,
}

impl DeviceManager {
    pub fn new() -> (Self, mpsc::Receiver<DeviceManagerEvent>) {
        let (event_tx, event_rx) = mpsc::channel(64);
        (
            Self {
                devices: Arc::new(DashMap::new()),
                event_tx,
            },
            event_rx,
        )
    }

    /// Start listening for USB device events from usbmuxd.
    pub async fn start_usb_discovery(&self) -> Result<(), remo_usbmuxd::UsbmuxError> {
        let client = UsbmuxClient::connect().await?;
        let (mut rx, _handle) = client.listen().await?;

        let devices = Arc::clone(&self.devices);
        let event_tx = self.event_tx.clone();

        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                match event {
                    DeviceEvent::Attached(dev) => {
                        let id = DeviceId::Usb(dev.device_id);
                        let info = DeviceInfo {
                            id: id.clone(),
                            display_name: format!("USB:{}", dev.serial),
                            transport: DeviceTransport::Usb { device: dev },
                        };
                        info!(device = %id, "USB device attached");
                        devices.insert(id.clone(), info.clone());
                        let _ = event_tx.send(DeviceManagerEvent::DeviceAdded(info)).await;
                    }
                    DeviceEvent::Detached { device_id } => {
                        let id = DeviceId::Usb(device_id);
                        info!(device = %id, "USB device detached");
                        devices.remove(&id);
                        let _ = event_tx.send(DeviceManagerEvent::DeviceRemoved(id)).await;
                    }
                    DeviceEvent::Unknown(_) => {}
                }
            }
        });

        Ok(())
    }

    /// Start Bonjour service discovery for simulators and Wi-Fi devices.
    pub fn start_bonjour_discovery(&self) -> Result<(), remo_bonjour::BonjourError> {
        let (browser, mut rx) = ServiceBrowser::browse(remo_bonjour::SERVICE_TYPE)?;

        let devices = Arc::clone(&self.devices);
        let event_tx = self.event_tx.clone();

        tokio::spawn(async move {
            let _browser = browser;
            while let Some(event) = rx.recv().await {
                match event {
                    BrowseEvent::Found(svc) => {
                        let id = DeviceId::Bonjour(svc.name.clone());
                        let info = DeviceInfo {
                            id: id.clone(),
                            display_name: svc.name.clone(),
                            transport: DeviceTransport::Bonjour {
                                host: svc.host.clone(),
                                port: svc.port,
                            },
                        };
                        info!(
                            device = %id,
                            host = %svc.host,
                            port = svc.port,
                            "Bonjour service found"
                        );
                        devices.insert(id.clone(), info.clone());
                        let _ = event_tx.send(DeviceManagerEvent::DeviceAdded(info)).await;
                    }
                    BrowseEvent::Lost { name } => {
                        let id = DeviceId::Bonjour(name);
                        info!(device = %id, "Bonjour service lost");
                        devices.remove(&id);
                        let _ = event_tx.send(DeviceManagerEvent::DeviceRemoved(id)).await;
                    }
                }
            }
        });

        Ok(())
    }

    /// Connect to a device by its `DeviceId`.
    pub async fn connect(
        &self,
        id: &DeviceId,
        event_tx: mpsc::Sender<remo_protocol::Event>,
    ) -> Result<RpcClient, Box<dyn std::error::Error>> {
        let info = self
            .devices
            .get(id)
            .ok_or_else(|| format!("device not found: {id}"))?
            .clone();

        match &info.transport {
            DeviceTransport::Usb { device } => {
                let client = UsbmuxClient::connect().await?;
                let tunnel = client
                    .connect_to_device(device.device_id, DEFAULT_DEVICE_PORT)
                    .await?;
                let label: SocketAddr = ([0, 0, 0, 0], DEFAULT_DEVICE_PORT).into();
                let conn = Connection::from_unix_stream(tunnel, label);
                Ok(RpcClient::from_connection(conn, event_tx)?)
            }
            DeviceTransport::Bonjour { host, port } => {
                let addr = info
                    .addr()
                    .ok_or_else(|| format!("cannot resolve {host}:{port}"))?;
                Ok(RpcClient::connect(addr, event_tx).await?)
            }
            DeviceTransport::Manual { addr } => Ok(RpcClient::connect(*addr, event_tx).await?),
        }
    }

    /// Connect directly to a known address (backward compat).
    pub async fn connect_direct(
        &self,
        addr: SocketAddr,
        event_tx: mpsc::Sender<remo_protocol::Event>,
    ) -> Result<RpcClient, Box<dyn std::error::Error>> {
        Ok(RpcClient::connect(addr, event_tx).await?)
    }

    /// Connect to a USB device by device_id (backward compat).
    pub async fn connect_to_device(
        &self,
        device_id: u32,
        event_tx: mpsc::Sender<remo_protocol::Event>,
    ) -> Result<RpcClient, Box<dyn std::error::Error>> {
        self.connect(&DeviceId::Usb(device_id), event_tx).await
    }

    /// List all currently known devices.
    pub fn list_devices(&self) -> Vec<DeviceInfo> {
        self.devices.iter().map(|e| e.value().clone()).collect()
    }
}
