use std::net::SocketAddr;
use std::time::Duration;

use anyhow::Result;
use clap::{Parser, Subcommand};
use remo_desktop::{DeviceManager, DeviceTransport, RpcClient};
use tokio::sync::mpsc;
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "remo", about = "Remote control bridge for iOS devices")]
struct Cli {
    /// Verbosity (-v, -vv, -vvv)
    #[arg(short, long, action = clap::ArgAction::Count)]
    verbose: u8,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// List connected iOS devices (USB + Bonjour).
    Devices,

    /// Call a capability on a device.
    Call {
        /// Device address (host:port). For simulator: 127.0.0.1:9930
        #[arg(short, long, default_value = "127.0.0.1:9930")]
        addr: SocketAddr,

        /// USB device ID (from `remo devices`). Overrides --addr.
        #[arg(short, long)]
        device: Option<u32>,

        /// Capability name to invoke.
        capability: String,

        /// JSON parameters (optional).
        #[arg(default_value = "{}")]
        params: String,

        /// Timeout in seconds.
        #[arg(short, long, default_value = "10")]
        timeout: u64,
    },

    /// List capabilities registered on a device.
    List {
        /// Device address.
        #[arg(short, long, default_value = "127.0.0.1:9930")]
        addr: SocketAddr,

        /// USB device ID (from `remo devices`). Overrides --addr.
        #[arg(short, long)]
        device: Option<u32>,
    },

    /// Watch events from a device.
    Watch {
        /// Device address.
        #[arg(short, long, default_value = "127.0.0.1:9930")]
        addr: SocketAddr,

        /// USB device ID (from `remo devices`). Overrides --addr.
        #[arg(short, long)]
        device: Option<u32>,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    let filter = match cli.verbose {
        0 => "remo=info",
        1 => "remo=debug",
        _ => "remo=trace",
    };
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::new(filter))
        .init();

    match cli.command {
        Command::Devices => cmd_devices().await?,
        Command::Call {
            addr,
            device,
            capability,
            params,
            timeout,
        } => {
            let params: serde_json::Value = serde_json::from_str(&params)?;
            let (event_tx, _event_rx) = mpsc::channel(16);
            let client = connect(device, addr, event_tx).await?;

            let target = device
                .map(|d| format!("device:{d}"))
                .unwrap_or_else(|| addr.to_string());
            println!("Calling '{capability}' on {target}...");
            let response = client
                .call(&capability, params, Duration::from_secs(timeout))
                .await?;
            let json = serde_json::to_string_pretty(&response)?;
            println!("{json}");
        }
        Command::List { addr, device } => {
            let (event_tx, _) = mpsc::channel(16);
            let client = connect(device, addr, event_tx).await?;

            let response = client
                .call(
                    "__list_capabilities",
                    serde_json::json!({}),
                    Duration::from_secs(5),
                )
                .await?;
            let json = serde_json::to_string_pretty(&response)?;
            println!("{json}");
        }
        Command::Watch { addr, device } => {
            let (event_tx, mut event_rx) = mpsc::channel(64);
            let _client = connect(device, addr, event_tx).await?;

            let target = device
                .map(|d| format!("device:{d}"))
                .unwrap_or_else(|| addr.to_string());
            println!("Watching events from {target} (Ctrl+C to stop)...");
            while let Some(event) = event_rx.recv().await {
                let json = serde_json::to_string(&event)?;
                println!("[event] {json}");
            }
        }
    }

    Ok(())
}

/// Connect via USB tunnel (if --device given) or direct TCP.
async fn connect(
    device: Option<u32>,
    addr: SocketAddr,
    event_tx: mpsc::Sender<remo_protocol::Event>,
) -> Result<RpcClient> {
    match device {
        Some(device_id) => {
            let (dm, _rx) = DeviceManager::new();
            let client = dm
                .connect_to_device(device_id, event_tx)
                .await
                .map_err(|e| anyhow::anyhow!("USB connect failed: {e}"))?;
            Ok(client)
        }
        None => {
            let client = RpcClient::connect(addr, event_tx).await?;
            Ok(client)
        }
    }
}

async fn cmd_devices() -> Result<()> {
    let (dm, mut event_rx) = DeviceManager::new();

    if let Err(e) = dm.start_usb_discovery().await {
        eprintln!("USB discovery unavailable: {e}");
    }

    if let Err(e) = dm.start_bonjour_discovery() {
        eprintln!("Bonjour discovery unavailable: {e}");
    }

    println!("Scanning for devices (3 seconds)...\n");

    let _ = tokio::time::timeout(Duration::from_secs(3), async {
        while (event_rx.recv().await).is_some() {}
    })
    .await;

    let devices = dm.list_devices();
    if devices.is_empty() {
        println!("No devices found.");
    } else {
        println!("{:<16} {:<30} {:<20}", "TYPE", "NAME", "ADDRESS");
        for dev in &devices {
            let addr_str = dev
                .addr()
                .map(|a| a.to_string())
                .unwrap_or_else(|| "N/A (USB tunnel)".into());
            let transport = match &dev.transport {
                DeviceTransport::Usb { .. } => "USB",
                DeviceTransport::Bonjour { .. } => "Bonjour",
                DeviceTransport::Manual { .. } => "Manual",
            };
            println!("{:<16} {:<30} {:<20}", transport, dev.display_name, addr_str);
        }
    }

    Ok(())
}
