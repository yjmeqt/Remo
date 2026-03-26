use std::io;
use std::path::PathBuf;
use std::sync::Arc;

use chrono::Utc;
use serde_json::json;
use tokio::net::TcpListener;
use tokio::sync::mpsc;
use tracing::{info, warn};

use remo_desktop::{DeviceManager, DeviceManagerEvent};

use crate::api::{self, ApiState};
use crate::connection_pool::ConnectionPool;
use crate::event_bus::EventBus;
use crate::types::{device_id_to_string, DaemonInfo, Webhook};

// ---------------------------------------------------------------------------
// Daemon
// ---------------------------------------------------------------------------

/// Top-level daemon orchestrator.
pub struct Daemon {
    port: u16,
    pool: Arc<ConnectionPool>,
    event_bus: Arc<EventBus>,
}

impl Daemon {
    /// Create a new `Daemon` bound to the given port.
    pub fn new(port: u16) -> Self {
        Self {
            port,
            pool: Arc::new(ConnectionPool::new()),
            event_bus: Arc::new(EventBus::new(1024)),
        }
    }

    /// Main entry point — runs the daemon until shutdown.
    pub async fn run(self) -> Result<(), Box<dyn std::error::Error>> {
        // (a) Write daemon.json
        let daemon_info = DaemonInfo {
            pid: std::process::id(),
            port: self.port,
            started_at: Utc::now(),
        };
        write_daemon_info(&daemon_info)?;
        info!(pid = daemon_info.pid, port = self.port, "daemon started");

        // (b) Start device discovery
        let (device_manager, mut device_rx) = DeviceManager::new();
        let device_manager = Arc::new(device_manager);

        if let Err(e) = device_manager.start_bonjour_discovery() {
            warn!(error = %e, "failed to start Bonjour discovery");
        }
        if let Err(e) = device_manager.start_usb_discovery().await {
            warn!(error = %e, "failed to start USB discovery");
        }

        info!("device discovery started");

        // (c) Spawn device event handler task
        let pool = Arc::clone(&self.pool);
        let event_bus = Arc::clone(&self.event_bus);
        let dm = Arc::clone(&device_manager);
        tokio::spawn(async move {
            while let Some(event) = device_rx.recv().await {
                match event {
                    DeviceManagerEvent::DeviceAdded(info) => {
                        let id = info.id.clone();
                        let device_str = device_id_to_string(&id);

                        // Set initial state and store device info
                        pool.set_state(id.clone(), crate::types::DeviceState::Discovered);
                        pool.set_device_info(&id, info);

                        event_bus.emit(
                            "device_discovered",
                            Some(device_str.clone()),
                            json!({"device": device_str}),
                        );

                        // Spawn auto-connect task
                        let pool = Arc::clone(&pool);
                        let event_bus = Arc::clone(&event_bus);
                        let dm = Arc::clone(&dm);
                        tokio::spawn(async move {
                            pool.set_state(id.clone(), crate::types::DeviceState::Connecting);

                            // Create mpsc channel for RPC events from the device
                            let (rpc_tx, mut rpc_rx) = mpsc::channel::<remo_protocol::Event>(256);

                            match dm.connect(&id, rpc_tx).await {
                                Ok(client) => {
                                    let device_str = device_id_to_string(&id);
                                    pool.set_client(&id, client);

                                    event_bus.emit(
                                        "connection_established",
                                        Some(device_str.clone()),
                                        json!({"device": device_str}),
                                    );

                                    // Spawn event forwarder task: forward RPC events to EventBus
                                    let eb = Arc::clone(&event_bus);
                                    let ds = device_str.clone();
                                    tokio::spawn(async move {
                                        while let Some(rpc_event) = rpc_rx.recv().await {
                                            eb.emit(
                                                &rpc_event.kind,
                                                Some(ds.clone()),
                                                rpc_event.payload,
                                            );
                                        }
                                    });

                                    // Spawn keepalive
                                    pool.spawn_keepalive(id, event_bus);
                                }
                                Err(e) => {
                                    let device_str = device_id_to_string(&id);
                                    warn!(device = %device_str, error = %e, "auto-connect failed");
                                    pool.set_state(id, crate::types::DeviceState::Disconnected);
                                }
                            }
                        });
                    }
                    DeviceManagerEvent::DeviceRemoved(id) => {
                        let device_str = device_id_to_string(&id);
                        pool.remove(&id);
                        event_bus.emit(
                            "device_lost",
                            Some(device_str.clone()),
                            json!({"device": device_str}),
                        );
                    }
                }
            }
        });

        // (d) Create ApiState and build router
        let webhooks: Arc<std::sync::Mutex<Vec<Webhook>>> =
            Arc::new(std::sync::Mutex::new(Vec::new()));

        let api_state = Arc::new(ApiState {
            pool: Arc::clone(&self.pool),
            event_bus: Arc::clone(&self.event_bus),
            webhooks: Arc::clone(&webhooks),
        });

        let app = api::router(api_state);

        // (e) Spawn webhook dispatcher task
        let webhooks_for_dispatch = Arc::clone(&webhooks);
        let mut event_rx = self.event_bus.subscribe();
        let http_client = reqwest::Client::new();
        tokio::spawn(async move {
            loop {
                match event_rx.recv().await {
                    Ok(event) => {
                        let hooks: Vec<Webhook> = {
                            webhooks_for_dispatch
                                .lock()
                                .expect("webhooks lock poisoned")
                                .clone()
                        };

                        for hook in hooks {
                            // Check if the event matches the webhook filter
                            let matches = hook.filter.is_empty()
                                || hook.filter.iter().any(|f| f == &event.kind);
                            if !matches {
                                continue;
                            }

                            let client = http_client.clone();
                            let url = hook.url.clone();
                            let payload = event.clone();
                            tokio::spawn(async move {
                                if let Err(e) = client.post(&url).json(&payload).send().await {
                                    warn!(url = %url, error = %e, "webhook dispatch failed");
                                }
                            });
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                        warn!(n, "webhook dispatcher lagged, skipped events");
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                }
            }
        });

        // (f) Bind axum server
        let addr = format!("127.0.0.1:{}", self.port);
        let listener = TcpListener::bind(&addr).await?;
        info!(addr = %addr, "HTTP server listening");

        // (g) Serve with graceful shutdown
        axum::serve(listener, app)
            .with_graceful_shutdown(shutdown_signal())
            .await?;

        // (h) Clean up on shutdown
        info!("shutting down");
        remove_daemon_info();

        Ok(())
    }
}

/// Wait for Ctrl+C / SIGTERM.
async fn shutdown_signal() {
    let ctrl_c = tokio::signal::ctrl_c();

    #[cfg(unix)]
    {
        let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install SIGTERM handler");
        tokio::select! {
            _ = ctrl_c => { info!("received Ctrl+C"); }
            _ = sigterm.recv() => { info!("received SIGTERM"); }
        }
    }

    #[cfg(not(unix))]
    {
        ctrl_c.await.expect("failed to listen for Ctrl+C");
        info!("received Ctrl+C");
    }
}

// ---------------------------------------------------------------------------
// daemon.json helpers
// ---------------------------------------------------------------------------

/// Return the path to `~/.remo/daemon.json`.
fn daemon_json_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".remo").join("daemon.json")
}

/// Create the directory and write daemon info to disk.
fn write_daemon_info(info: &DaemonInfo) -> io::Result<()> {
    let path = daemon_json_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(info).expect("DaemonInfo is serializable");
    std::fs::write(&path, json)
}

/// Remove daemon.json from disk (best-effort).
fn remove_daemon_info() {
    let path = daemon_json_path();
    let _ = std::fs::remove_file(path);
}

/// Read daemon info from `~/.remo/daemon.json`, returning `None` if the file
/// doesn't exist or cannot be parsed.
pub fn read_daemon_info() -> Option<DaemonInfo> {
    let path = daemon_json_path();
    let data = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&data).ok()
}

/// Check whether a daemon with the given PID is still alive.
#[cfg(unix)]
pub fn is_daemon_alive(info: &DaemonInfo) -> bool {
    // SAFETY: `kill(pid, 0)` with signal 0 only checks whether the process
    // exists and is reachable — it does not actually send any signal.
    #[allow(unsafe_code)]
    unsafe {
        libc::kill(info.pid as i32, 0) == 0
    }
}

/// Non-unix fallback — cannot check process liveness.
#[cfg(not(unix))]
pub fn is_daemon_alive(_info: &DaemonInfo) -> bool {
    false
}

/// Public wrapper for removing daemon.json (used by CLI stop command).
pub fn remove_daemon_info_public() {
    remove_daemon_info();
}
