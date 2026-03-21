use std::net::SocketAddr;

use remo_protocol::{ErrorCode, Message, Request, Response};
use remo_transport::{Connection, Listener};
use tokio::sync::broadcast;
use tracing::{error, info, warn};

use crate::registry::CapabilityRegistry;

/// The embedded RPC server running inside the iOS app.
pub struct RemoServer {
    registry: CapabilityRegistry,
    port: u16,
    shutdown_tx: broadcast::Sender<()>,
}

impl RemoServer {
    pub fn new(registry: CapabilityRegistry, port: u16) -> Self {
        let (shutdown_tx, _) = broadcast::channel(1);

        // Register built-in capabilities.
        let reg = registry.clone();
        registry.register_sync("__list_capabilities", move |_| {
            Ok(serde_json::json!(reg.list()))
        });

        registry.register_sync("__ping", |_| Ok(serde_json::json!({"pong": true})));

        Self {
            registry,
            port,
            shutdown_tx,
        }
    }

    /// Return a clone of the shutdown sender for external use.
    pub fn shutdown_handle(&self) -> broadcast::Sender<()> {
        self.shutdown_tx.clone()
    }

    /// Start accepting connections. Blocks until shutdown.
    pub async fn run(&self) -> Result<(), remo_transport::TransportError> {
        let addr: SocketAddr = ([0, 0, 0, 0], self.port).into();
        let listener = Listener::bind(addr).await?;
        info!(port = self.port, "remo server started");

        loop {
            let mut shutdown_rx = self.shutdown_tx.subscribe();

            tokio::select! {
                result = listener.accept() => {
                    match result {
                        Ok(conn) => {
                            let registry = self.registry.clone();
                            let mut shutdown_rx = self.shutdown_tx.subscribe();
                            tokio::spawn(async move {
                                tokio::select! {
                                    _ = handle_connection(conn, registry) => {}
                                    _ = shutdown_rx.recv() => {
                                        info!("connection handler shutting down");
                                    }
                                }
                            });
                        }
                        Err(e) => {
                            error!("accept error: {e}");
                        }
                    }
                }
                _ = shutdown_rx.recv() => {
                    info!("remo server shutting down");
                    break;
                }
            }
        }

        Ok(())
    }

    /// Signal the server to shut down.
    pub fn shutdown(&self) {
        let _ = self.shutdown_tx.send(());
    }
}

async fn handle_connection(mut conn: Connection, registry: CapabilityRegistry) {
    let peer = conn.peer_addr();
    info!(%peer, "handling connection");

    loop {
        let msg = match conn.recv().await {
            Ok(Some(msg)) => msg,
            Ok(None) => {
                info!(%peer, "connection closed");
                break;
            }
            Err(e) => {
                warn!(%peer, "read error: {e}");
                break;
            }
        };

        match msg {
            Message::Request(req) => {
                let response = dispatch_request(&registry, req).await;
                if let Err(e) = conn.send(Message::Response(response)).await {
                    warn!(%peer, "write error: {e}");
                    break;
                }
            }
            other => {
                warn!(%peer, "unexpected message type: {other:?}");
            }
        }
    }
}

async fn dispatch_request(registry: &CapabilityRegistry, req: Request) -> Response {
    let Request {
        id,
        capability,
        params,
    } = req;

    match registry.invoke(&capability, params).await {
        Some(Ok(data)) => Response::ok(id, data),
        Some(Err(e)) => {
            let code = match &e {
                crate::registry::HandlerError::InvalidParams(_) => ErrorCode::InvalidParams,
                crate::registry::HandlerError::Internal(_) => ErrorCode::Internal,
            };
            Response::error(id, code, e.to_string())
        }
        None => Response::error(
            id,
            ErrorCode::NotFound,
            format!("capability '{capability}' not found"),
        ),
    }
}
