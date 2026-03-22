use std::net::SocketAddr;
use std::time::Duration;

use anyhow::Result;
use base64::Engine;
use clap::{Parser, Subcommand};
use remo_desktop::{DeviceManager, DeviceTransport, RpcClient};
use remo_protocol::ResponseResult;
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

    /// Dump the view hierarchy tree.
    Tree {
        /// Device address.
        #[arg(short, long, default_value = "127.0.0.1:9930")]
        addr: SocketAddr,

        /// USB device ID (from `remo devices`). Overrides --addr.
        #[arg(short, long)]
        device: Option<u32>,

        /// Maximum depth to traverse (omit for full tree).
        #[arg(short, long)]
        max_depth: Option<u64>,
    },

    /// Take a screenshot of the device.
    Screenshot {
        /// Device address.
        #[arg(short, long, default_value = "127.0.0.1:9930")]
        addr: SocketAddr,

        /// USB device ID (from `remo devices`). Overrides --addr.
        #[arg(short = 'D', long)]
        device: Option<u32>,

        /// Output file path.
        #[arg(short, long, default_value = "screenshot.jpg")]
        output: String,

        /// Image format: jpeg or png.
        #[arg(short, long, default_value = "jpeg")]
        format: String,

        /// JPEG quality (0.0 - 1.0).
        #[arg(short, long, default_value = "0.8")]
        quality: f64,
    },

    /// Show device and app information.
    Info {
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
        Command::Tree {
            addr,
            device,
            max_depth,
        } => {
            cmd_tree(addr, device, max_depth).await?;
        }
        Command::Screenshot {
            addr,
            device,
            output,
            format,
            quality,
        } => {
            cmd_screenshot(addr, device, &output, &format, quality).await?;
        }
        Command::Info { addr, device } => {
            cmd_info(addr, device).await?;
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
            let (dm, mut rx) = DeviceManager::new();
            dm.start_usb_discovery()
                .await
                .map_err(|e| anyhow::anyhow!("USB discovery failed: {e}"))?;
            // Wait briefly for device attachment events
            let _ = tokio::time::timeout(Duration::from_secs(2), async {
                while (rx.recv().await).is_some() {}
            })
            .await;
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
            println!(
                "{:<16} {:<30} {:<20}",
                transport, dev.display_name, addr_str
            );
        }
    }

    Ok(())
}

async fn cmd_tree(addr: SocketAddr, device: Option<u32>, max_depth: Option<u64>) -> Result<()> {
    let (event_tx, _) = mpsc::channel(16);
    let client = connect(device, addr, event_tx).await?;

    let mut params = serde_json::json!({});
    if let Some(d) = max_depth {
        params["max_depth"] = serde_json::json!(d);
    }

    let response = client
        .call("__view_tree", params, Duration::from_secs(10))
        .await?;

    match response.result {
        ResponseResult::Ok { data } => {
            if data.is_null() {
                println!("No key window found.");
            } else {
                print_tree(&data, 0);
            }
        }
        ResponseResult::Error { message, .. } => {
            anyhow::bail!("view tree failed: {message}");
        }
    }

    Ok(())
}

fn print_tree(node: &serde_json::Value, indent: usize) {
    let prefix = "  ".repeat(indent);
    let class = node["class_name"].as_str().unwrap_or("?");
    let frame = &node["frame"];
    let x = frame["x"].as_f64().unwrap_or(0.0);
    let y = frame["y"].as_f64().unwrap_or(0.0);
    let w = frame["width"].as_f64().unwrap_or(0.0);
    let h = frame["height"].as_f64().unwrap_or(0.0);

    let mut extras = Vec::new();
    if node["is_hidden"].as_bool() == Some(true) {
        extras.push("hidden".to_string());
    }
    let alpha = node["alpha"].as_f64().unwrap_or(1.0);
    if alpha < 1.0 {
        extras.push(format!("alpha={alpha:.1}"));
    }
    if let Some(aid) = node["accessibility_id"].as_str() {
        extras.push(format!("id=\"{aid}\""));
    }

    let extra_str = if extras.is_empty() {
        String::new()
    } else {
        format!(" [{}]", extras.join(", "))
    };

    println!("{prefix}{class} ({x:.0}, {y:.0}, {w:.0}x{h:.0}){extra_str}");

    if let Some(children) = node["children"].as_array() {
        for child in children {
            print_tree(child, indent + 1);
        }
    }
}

async fn cmd_screenshot(
    addr: SocketAddr,
    device: Option<u32>,
    output: &str,
    format: &str,
    quality: f64,
) -> Result<()> {
    let (event_tx, _) = mpsc::channel(16);
    let client = connect(device, addr, event_tx).await?;

    let response = client
        .call(
            "__screenshot",
            serde_json::json!({"format": format, "quality": quality}),
            Duration::from_secs(15),
        )
        .await?;

    match response.result {
        ResponseResult::Ok { data } => {
            let b64 = data["image"]
                .as_str()
                .ok_or_else(|| anyhow::anyhow!("no image data in response"))?;
            let bytes = base64::engine::general_purpose::STANDARD.decode(b64)?;
            let w = data["width"].as_f64().unwrap_or(0.0);
            let h = data["height"].as_f64().unwrap_or(0.0);
            let scale = data["scale"].as_f64().unwrap_or(1.0);

            std::fs::write(output, &bytes)?;
            println!(
                "Screenshot saved to {output} ({} bytes, {w:.0}x{h:.0} @{scale:.0}x)",
                bytes.len()
            );
        }
        ResponseResult::Error { message, .. } => {
            anyhow::bail!("screenshot failed: {message}");
        }
    }

    Ok(())
}

async fn cmd_info(addr: SocketAddr, device: Option<u32>) -> Result<()> {
    let (event_tx, _) = mpsc::channel(16);
    let client = connect(device, addr, event_tx).await?;

    let dev_resp = client
        .call(
            "__device_info",
            serde_json::json!({}),
            Duration::from_secs(5),
        )
        .await?;
    let app_resp = client
        .call("__app_info", serde_json::json!({}), Duration::from_secs(5))
        .await?;

    println!("=== Device ===");
    if let ResponseResult::Ok { data } = &dev_resp.result {
        println!("  Name:    {}", data["name"].as_str().unwrap_or("unknown"));
        println!("  Model:   {}", data["model"].as_str().unwrap_or("unknown"));
        println!(
            "  OS:      {} {}",
            data["system_name"].as_str().unwrap_or("?"),
            data["system_version"].as_str().unwrap_or("?")
        );
        println!(
            "  Screen:  {:.0}x{:.0} @{:.0}x",
            data["screen_width"].as_f64().unwrap_or(0.0),
            data["screen_height"].as_f64().unwrap_or(0.0),
            data["screen_scale"].as_f64().unwrap_or(1.0),
        );
    }

    println!("\n=== App ===");
    if let ResponseResult::Ok { data } = &app_resp.result {
        println!(
            "  Name:    {}",
            data["display_name"].as_str().unwrap_or("unknown")
        );
        println!(
            "  Bundle:  {}",
            data["bundle_id"].as_str().unwrap_or("unknown")
        );
        println!(
            "  Version: {} ({})",
            data["version"].as_str().unwrap_or("?"),
            data["build"].as_str().unwrap_or("?")
        );
    }

    Ok(())
}
