use std::sync::atomic::{AtomicU32, Ordering};

use futures::{SinkExt, StreamExt};
use remo_core::types::{ConnectionType, DeviceInfo};
use remo_core::RemoError;
use tokio::net::TcpStream;
use tokio_util::codec::Framed;

use super::protocol::{
    build_connect, build_list_devices, build_listen, UsbmuxdCodec, UsbmuxdPacket,
};

const USBMUXD_TCP_PORT: u16 = 27015;

/// Async client for the usbmuxd daemon.
///
/// On macOS, usbmuxd listens on a Unix domain socket at `/var/run/usbmuxd`.
/// For cross-platform testing, this client connects over TCP (usbmuxd can
/// also listen on port 27015 on some configurations, or via a TCP proxy).
pub struct UsbmuxdClient {
    framed: Framed<TcpStream, UsbmuxdCodec>,
    next_tag: AtomicU32,
}

impl UsbmuxdClient {
    /// Connect to usbmuxd over TCP.
    pub async fn connect_tcp(addr: &str) -> Result<Self, RemoError> {
        let stream = TcpStream::connect(addr).await?;
        Ok(Self {
            framed: Framed::new(stream, UsbmuxdCodec),
            next_tag: AtomicU32::new(1),
        })
    }

    /// Connect to the default usbmuxd TCP port on localhost.
    pub async fn connect_default() -> Result<Self, RemoError> {
        Self::connect_tcp(&format!("127.0.0.1:{USBMUXD_TCP_PORT}")).await
    }

    fn next_tag(&self) -> u32 {
        self.next_tag.fetch_add(1, Ordering::SeqCst)
    }

    async fn send(&mut self, pkt: UsbmuxdPacket) -> Result<(), RemoError> {
        self.framed.send(pkt).await.map_err(RemoError::Io)
    }

    async fn recv(&mut self) -> Result<UsbmuxdPacket, RemoError> {
        self.framed
            .next()
            .await
            .ok_or(RemoError::Protocol("connection closed".into()))?
            .map_err(RemoError::Io)
    }

    /// Query usbmuxd for the list of currently connected USB devices.
    pub async fn list_devices(&mut self) -> Result<Vec<DeviceInfo>, RemoError> {
        let tag = self.next_tag();
        self.send(build_list_devices(tag)).await?;
        let resp = self.recv().await?;
        let dict = resp
            .parse_plist()
            .map_err(RemoError::Protocol)?;

        let device_list = dict
            .get("DeviceList")
            .and_then(|v| v.as_array())
            .ok_or_else(|| RemoError::Protocol("missing DeviceList".into()))?;

        let mut devices = Vec::new();
        for entry in device_list {
            if let Some(props) = entry
                .as_dictionary()
                .and_then(|d| d.get("Properties"))
                .and_then(|v| v.as_dictionary())
            {
                let device_id = entry
                    .as_dictionary()
                    .and_then(|d| d.get("DeviceID"))
                    .and_then(|v| v.as_unsigned_integer())
                    .unwrap_or(0) as u32;

                let serial = props
                    .get("SerialNumber")
                    .and_then(|v| v.as_string())
                    .unwrap_or("")
                    .to_string();

                let product_id = props
                    .get("ProductID")
                    .and_then(|v| v.as_unsigned_integer())
                    .unwrap_or(0) as u16;

                let conn_type = match props
                    .get("ConnectionType")
                    .and_then(|v| v.as_string())
                {
                    Some("USB") => ConnectionType::Usb,
                    Some("Network") => ConnectionType::Network,
                    _ => ConnectionType::Usb,
                };

                devices.push(DeviceInfo {
                    device_id,
                    serial_number: serial,
                    product_id,
                    connection_type: conn_type,
                });
            }
        }

        Ok(devices)
    }

    /// Subscribe to device attach/detach events.
    pub async fn listen(&mut self) -> Result<(), RemoError> {
        let tag = self.next_tag();
        self.send(build_listen(tag)).await?;
        let resp = self.recv().await?;
        let dict = resp
            .parse_plist()
            .map_err(RemoError::Protocol)?;

        let number = dict
            .get("Number")
            .and_then(|v| v.as_unsigned_integer())
            .unwrap_or(u64::MAX);

        if number != 0 {
            return Err(RemoError::Protocol(format!(
                "Listen failed with result: {number}"
            )));
        }
        Ok(())
    }

    /// Connect to a device port through usbmuxd.
    ///
    /// On success, the underlying TCP stream is now a tunnel to the device.
    /// The caller should take ownership of the stream for further I/O.
    pub async fn connect_to_device(
        &mut self,
        device_id: u32,
        port: u16,
    ) -> Result<(), RemoError> {
        let tag = self.next_tag();
        self.send(build_connect(tag, device_id, port)).await?;
        let resp = self.recv().await?;
        let dict = resp
            .parse_plist()
            .map_err(RemoError::Protocol)?;

        let number = dict
            .get("Number")
            .and_then(|v| v.as_unsigned_integer())
            .unwrap_or(u64::MAX);

        if number != 0 {
            return Err(RemoError::ConnectionRefused);
        }
        Ok(())
    }

    /// Take the underlying TCP stream (e.g. after a successful `connect_to_device`).
    pub fn into_inner(self) -> TcpStream {
        self.framed.into_inner()
    }
}

/// Parse device event plists from the Listen stream.
pub fn parse_device_event(dict: &plist::Dictionary) -> Option<DeviceEvent> {
    let msg_type = dict.get("MessageType")?.as_string()?;
    match msg_type {
        "Attached" => {
            let props = dict.get("Properties")?.as_dictionary()?;
            let device_id = dict
                .get("DeviceID")
                .and_then(|v| v.as_unsigned_integer())
                .unwrap_or(0) as u32;
            let serial = props
                .get("SerialNumber")
                .and_then(|v| v.as_string())
                .unwrap_or("")
                .to_string();
            let product_id = props
                .get("ProductID")
                .and_then(|v| v.as_unsigned_integer())
                .unwrap_or(0) as u16;

            Some(DeviceEvent::Attached(DeviceInfo {
                device_id,
                serial_number: serial,
                product_id,
                connection_type: ConnectionType::Usb,
            }))
        }
        "Detached" => {
            let device_id = dict
                .get("DeviceID")
                .and_then(|v| v.as_unsigned_integer())
                .unwrap_or(0) as u32;
            Some(DeviceEvent::Detached(device_id))
        }
        _ => None,
    }
}

#[derive(Debug, Clone)]
pub enum DeviceEvent {
    Attached(DeviceInfo),
    Detached(u32),
}
