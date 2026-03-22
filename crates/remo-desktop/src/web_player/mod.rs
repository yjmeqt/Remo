//! Local web server for browser-based mirror playback.
//!
//! - `GET /` serves the embedded HTML/JS player
//! - `WS /stream` pushes raw H.264 NAL frames as binary WebSocket messages

use std::net::SocketAddr;
use std::sync::Arc;

use axum::extract::ws::{Message, WebSocket};
use axum::extract::{State, WebSocketUpgrade};
use axum::response::Html;
use axum::routing::get;
use axum::Router;
use remo_protocol::{stream_flags, StreamFrame};
use tokio::sync::broadcast;
use tracing::{debug, info, warn};

struct PlayerState {
    stream_tx: broadcast::Sender<StreamFrame>,
}

/// Start the web player HTTP server. Returns the bound address.
pub async fn start_server(
    stream_tx: broadcast::Sender<StreamFrame>,
    bind_addr: SocketAddr,
    shutdown: impl std::future::Future<Output = ()> + Send + 'static,
) -> std::io::Result<SocketAddr> {
    let state = Arc::new(PlayerState { stream_tx });

    let app = Router::new()
        .route("/", get(serve_player))
        .route("/stream", get(ws_handler))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(bind_addr).await?;
    let addr = listener.local_addr()?;
    info!(%addr, "web player server started");

    tokio::spawn(async move {
        axum::serve(listener, app)
            .with_graceful_shutdown(shutdown)
            .await
            .ok();
    });

    Ok(addr)
}

async fn serve_player() -> Html<&'static str> {
    Html(include_str!("player.html"))
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<PlayerState>>,
) -> impl axum::response::IntoResponse {
    let rx = state.stream_tx.subscribe();
    ws.on_upgrade(move |socket| handle_ws(socket, rx))
}

async fn handle_ws(mut socket: WebSocket, mut rx: broadcast::Receiver<StreamFrame>) {
    debug!("WebSocket client connected");
    loop {
        match rx.recv().await {
            Ok(frame) => {
                if frame.flags & stream_flags::STREAM_END != 0 {
                    break;
                }
                // Binary format: [flags(1B)][timestamp_us(8B)][nal_data...]
                let mut buf = Vec::with_capacity(1 + 8 + frame.data.len());
                buf.push(frame.flags);
                buf.extend_from_slice(&frame.timestamp_us.to_be_bytes());
                buf.extend_from_slice(&frame.data);
                if socket.send(Message::Binary(buf.into())).await.is_err() {
                    break;
                }
            }
            Err(broadcast::error::RecvError::Lagged(n)) => {
                warn!(n, "WebSocket client lagged, skipped frames");
            }
            Err(broadcast::error::RecvError::Closed) => break,
        }
    }
    debug!("WebSocket client disconnected");
}
