use std::net::SocketAddr;
use std::sync::Arc;

use futures::{SinkExt, StreamExt};
use remo_core::protocol::{read_handshake, write_handshake, RemoCodec};
use remo_core::{Message, RemoError};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;
use tokio_util::codec::Framed;

use crate::registry::CapabilityRegistry;

/// TCP server that runs on the iOS device (or standalone for testing).
///
/// Accepts connections from Remo host clients, performs handshake,
/// and dispatches incoming requests to the capability registry.
pub struct AgentServer {
    listener: TcpListener,
    registry: Arc<CapabilityRegistry>,
}

impl AgentServer {
    /// Bind to the given address and prepare to accept connections.
    pub async fn bind(addr: &str, registry: CapabilityRegistry) -> Result<Self, RemoError> {
        let listener = TcpListener::bind(addr).await?;
        tracing::info!("agent bound to {}", listener.local_addr()?);
        Ok(Self {
            listener,
            registry: Arc::new(registry),
        })
    }

    pub fn local_addr(&self) -> SocketAddr {
        self.listener.local_addr().expect("bound address")
    }

    /// Run the server loop, accepting connections until cancelled.
    pub async fn run(&self) -> Result<(), RemoError> {
        loop {
            let (stream, peer) = self.listener.accept().await?;
            tracing::info!("new connection from {peer}");
            let registry = self.registry.clone();
            tokio::spawn(async move {
                if let Err(e) = handle_connection(stream, registry).await {
                    tracing::warn!("connection {peer} error: {e}");
                }
                tracing::info!("connection {peer} closed");
            });
        }
    }
}

async fn handle_connection(
    mut stream: TcpStream,
    registry: Arc<CapabilityRegistry>,
) -> Result<(), RemoError> {
    // Handshake
    write_handshake(&mut stream).await?;
    let peer_version = read_handshake(&mut stream).await?;
    tracing::debug!("peer protocol version: {peer_version}");

    let framed = Framed::new(stream, RemoCodec);
    let (sink, mut stream) = framed.split();

    // Writer task: collects responses from handlers and sends them out.
    let (tx, mut rx) = mpsc::channel::<Message>(64);
    let writer_handle = tokio::spawn(async move {
        let mut sink = sink;
        while let Some(msg) = rx.recv().await {
            if sink.send(msg).await.is_err() {
                break;
            }
        }
    });

    // Send capabilities event immediately after handshake.
    let caps = registry.list();
    let caps_json = serde_json::to_value(&caps).unwrap_or_default();
    let _ = tx
        .send(Message::event(0, "capabilities", caps_json))
        .await;

    // Read requests and dispatch to handlers concurrently.
    while let Some(frame) = stream.next().await {
        let msg = frame?;
        match msg {
            Message::Request { id, body } => {
                let cap_name = body.capability.clone();
                if cap_name == "_list_capabilities" {
                    let caps = registry.list();
                    let data =
                        serde_json::to_value(&caps).unwrap_or_default();
                    let _ = tx.send(Message::response_ok(id, data)).await;
                    continue;
                }

                let registry = registry.clone();
                let tx = tx.clone();
                tokio::spawn(async move {
                    let result = registry.invoke(&cap_name, body.params).await;
                    let resp = match result {
                        Ok(data) => Message::response_ok(id, data),
                        Err(e) => Message::response_err(id, e),
                    };
                    let _ = tx.send(resp).await;
                });
            }
            _ => {
                tracing::debug!("ignoring non-request message");
            }
        }
    }

    drop(tx);
    let _ = writer_handle.await;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use remo_core::protocol::write_handshake as client_write_handshake;
    use remo_core::protocol::read_handshake as client_read_handshake;
    use tokio::net::TcpStream;

    #[tokio::test]
    async fn test_agent_accepts_connection() {
        let mut registry = CapabilityRegistry::new();
        registry.register("echo", "echo", |p| async move { Ok(p) });

        let server = AgentServer::bind("127.0.0.1:0", registry)
            .await
            .unwrap();
        let addr = server.local_addr();

        let server_handle = tokio::spawn(async move { server.run().await });

        // Connect as a client
        let mut stream = TcpStream::connect(addr).await.unwrap();

        // Handshake: read server's, then write ours
        let ver = client_read_handshake(&mut stream).await.unwrap();
        assert_eq!(ver, remo_core::PROTOCOL_VERSION);
        client_write_handshake(&mut stream).await.unwrap();

        // Wrap in framed
        let mut framed = Framed::new(stream, RemoCodec);

        // Should receive capabilities event
        let msg = framed.next().await.unwrap().unwrap();
        if let Message::Event { body, .. } = msg {
            assert_eq!(body.name, "capabilities");
        } else {
            panic!("expected capabilities event, got {:?}", msg);
        }

        // Send echo request
        framed
            .send(Message::request(1, "echo", serde_json::json!({"test": 42})))
            .await
            .unwrap();

        let resp = framed.next().await.unwrap().unwrap();
        if let Message::Response { id, body } = resp {
            assert_eq!(id, 1);
            assert!(body.success);
            assert_eq!(body.data, serde_json::json!({"test": 42}));
        } else {
            panic!("expected response, got {:?}", resp);
        }

        server_handle.abort();
    }
}
