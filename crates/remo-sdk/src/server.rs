use std::net::SocketAddr;
use std::sync::Arc;

use remo_protocol::{ErrorCode, Message, Request, Response};
use remo_transport::{Connection, Listener};
use tokio::sync::{broadcast, oneshot, Mutex};
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

        register_builtins(&registry);

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
    ///
    /// If `port_tx` is provided, sends the actual bound port once listening.
    /// This is essential when `port` is 0 (OS-assigned dynamic port).
    pub async fn run(
        &self,
        port_tx: Option<oneshot::Sender<u16>>,
    ) -> Result<(), remo_transport::TransportError> {
        let addr: SocketAddr = ([0, 0, 0, 0], self.port).into();
        let listener = Listener::bind(addr).await?;
        let actual_port = listener.local_addr().port();
        info!(port = actual_port, "remo server started");

        if let Some(tx) = port_tx {
            let _ = tx.send(actual_port);
        }

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

// ---------------------------------------------------------------------------
// Built-in capabilities
// ---------------------------------------------------------------------------

#[allow(unsafe_code)]
fn register_builtins(registry: &CapabilityRegistry) {
    let reg = registry.clone();
    registry.register_sync("__list_capabilities", move |_| {
        Ok(serde_json::json!(reg.list()))
    });

    registry.register_sync("__ping", |_| Ok(serde_json::json!({"pong": true})));

    registry.register_sync("__view_tree", |params| {
        let depth: Option<usize> = params
            .get("max_depth")
            .and_then(serde_json::Value::as_u64)
            .map(|d| d as usize);

        let tree = remo_objc::run_on_main_sync(|| {
            // SAFETY: run_on_main_sync ensures main-thread execution.
            let full_tree = unsafe { remo_objc::snapshot_view_tree() };
            full_tree.map(|t| {
                if let Some(max) = depth {
                    truncate_tree(t, max, 0)
                } else {
                    t
                }
            })
        });

        Ok(serde_json::to_value(tree).unwrap_or_default())
    });

    registry.register_sync_raw("__screenshot", |params| {
        let format = params
            .get("format")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("jpeg");
        let quality = params
            .get("quality")
            .and_then(serde_json::Value::as_f64)
            .unwrap_or(0.8);

        let result = remo_objc::run_on_main_sync(|| {
            // SAFETY: run_on_main_sync ensures main-thread execution.
            unsafe { remo_objc::capture_screenshot(format, quality) }
        });

        match result {
            Some(sr) => Ok(crate::registry::HandlerOutput::Binary {
                metadata: serde_json::json!({
                    "format": sr.format,
                    "width": sr.width,
                    "height": sr.height,
                    "scale": sr.scale,
                    "size": sr.bytes.len(),
                }),
                data: sr.bytes,
            }),
            None => Err(crate::registry::HandlerError::Internal(
                "screenshot capture failed".into(),
            )),
        }
    });

    registry.register_sync("__device_info", |_| {
        let info = remo_objc::run_on_main_sync(|| {
            // SAFETY: run_on_main_sync ensures main-thread execution.
            unsafe { remo_objc::get_device_info() }
        });
        Ok(serde_json::to_value(info).unwrap_or_default())
    });

    registry.register_sync("__app_info", |_| {
        let info = remo_objc::run_on_main_sync(|| {
            // SAFETY: run_on_main_sync ensures main-thread execution.
            unsafe { remo_objc::get_app_info() }
        });
        Ok(serde_json::to_value(info).unwrap_or_default())
    });
}

fn truncate_tree(
    mut node: remo_objc::ViewNode,
    max_depth: usize,
    current: usize,
) -> remo_objc::ViewNode {
    if current >= max_depth {
        let count = count_descendants(&node);
        node.children.clear();
        if count > 0 {
            node.class_name = format!("{} (+{count} children)", node.class_name);
        }
    } else {
        node.children = node
            .children
            .into_iter()
            .map(|c| truncate_tree(c, max_depth, current + 1))
            .collect();
    }
    node
}

fn count_descendants(node: &remo_objc::ViewNode) -> usize {
    node.children.len() + node.children.iter().map(count_descendants).sum::<usize>()
}

// ---------------------------------------------------------------------------
// Connection handling
// ---------------------------------------------------------------------------

async fn handle_connection(conn: Connection, registry: CapabilityRegistry) {
    let peer = conn.peer_addr();
    info!(%peer, "handling connection");

    let (mut read_half, write_half) = conn.split();
    let write_half = Arc::new(Mutex::new(write_half));
    let sender = crate::streaming::StreamSender::new(Arc::clone(&write_half));

    // Active mirror session (only one at a time per connection)
    let mirror_session: Arc<Mutex<Option<Arc<crate::streaming::MirrorSession>>>> =
        Arc::new(Mutex::new(None));

    loop {
        let msg = match read_half.recv().await {
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
                let response_msg =
                    dispatch_request_with_streaming(&registry, req, &sender, &mirror_session).await;

                if let Err(e) = sender.send_message(response_msg).await {
                    warn!(%peer, "write error: {e}");
                    break;
                }
            }
            other => {
                warn!(%peer, "unexpected message type: {other:?}");
            }
        }
    }

    // Stop any active mirror session on disconnect
    let session = mirror_session.lock().await.take();
    if let Some(s) = session {
        s.stop();
    }
}

async fn dispatch_request_with_streaming(
    registry: &CapabilityRegistry,
    req: Request,
    sender: &crate::streaming::StreamSender,
    mirror_session: &Arc<Mutex<Option<Arc<crate::streaming::MirrorSession>>>>,
) -> Message {
    let Request {
        id,
        capability,
        params,
    } = req;

    match capability.as_str() {
        "__start_mirror" => {
            let mut session_guard = mirror_session.lock().await;
            if session_guard.is_some() {
                return Message::Response(Response::error(
                    id,
                    ErrorCode::StreamAlreadyActive,
                    "a mirror stream is already active",
                ));
            }

            let fps = params
                .get("fps")
                .and_then(serde_json::Value::as_u64)
                .unwrap_or(30)
                .clamp(1, 120) as u32;

            let stream_id = 1u32;
            let session = Arc::new(crate::streaming::MirrorSession::new(stream_id));
            *session_guard = Some(Arc::clone(&session));

            let sender_clone = sender.clone();
            tokio::spawn(async move {
                crate::streaming::run_mirror_loop(session, sender_clone, fps).await;
            });

            Message::Response(Response::ok(
                id,
                serde_json::json!({ "stream_id": stream_id }),
            ))
        }
        "__stop_mirror" => {
            let mut session_guard = mirror_session.lock().await;
            if let Some(session) = session_guard.take() {
                session.stop();
                Message::Response(Response::ok(id, serde_json::json!({ "stopped": true })))
            } else {
                Message::Response(Response::error(
                    id,
                    ErrorCode::NotFound,
                    "no active mirror stream",
                ))
            }
        }
        _ => {
            dispatch_request(
                registry,
                Request {
                    id,
                    capability,
                    params,
                },
            )
            .await
        }
    }
}

async fn dispatch_request(registry: &CapabilityRegistry, req: Request) -> Message {
    let Request {
        id,
        capability,
        params,
    } = req;

    match registry.invoke(&capability, params).await {
        Some(Ok(output)) => match output {
            crate::registry::HandlerOutput::Json(data) => Message::Response(Response::ok(id, data)),
            crate::registry::HandlerOutput::Binary { metadata, data } => {
                Message::BinaryResponse(remo_protocol::BinaryResponse::new(id, metadata, data))
            }
        },
        Some(Err(e)) => {
            let code = match &e {
                crate::registry::HandlerError::InvalidParams(_) => ErrorCode::InvalidParams,
                crate::registry::HandlerError::Internal(_) => ErrorCode::Internal,
            };
            Message::Response(Response::error(id, code, e.to_string()))
        }
        None => Message::Response(Response::error(
            id,
            ErrorCode::NotFound,
            format!("capability '{capability}' not found"),
        )),
    }
}
