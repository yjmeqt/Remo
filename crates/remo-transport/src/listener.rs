use std::net::SocketAddr;

use tokio::net::TcpListener;
use tracing::info;

use crate::connection::Connection;
use crate::TransportError;

/// A TCP server that accepts incoming `Connection`s.
pub struct Listener {
    inner: TcpListener,
    local_addr: SocketAddr,
}

impl Listener {
    /// Bind to the given address.
    pub async fn bind(addr: impl Into<SocketAddr>) -> Result<Self, TransportError> {
        let addr = addr.into();
        let inner = TcpListener::bind(addr).await?;
        let local_addr = inner.local_addr()?;
        info!(%local_addr, "remo listener started");
        Ok(Self { inner, local_addr })
    }

    /// Accept the next connection.
    pub async fn accept(&self) -> Result<Connection, TransportError> {
        let (stream, peer) = self.inner.accept().await?;
        info!(%peer, "accepted connection");
        Connection::new(stream)
    }

    pub fn local_addr(&self) -> SocketAddr {
        self.local_addr
    }
}
