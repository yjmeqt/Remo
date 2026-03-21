mod session;

use std::net::SocketAddr;

use anyhow::Result;
use clap::{Parser, Subcommand};
use session::DeviceSession;

#[derive(Parser)]
#[command(name = "remo", version, about = "Remo – iOS remote inspection & control")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Connect to a Remo agent and list capabilities
    Caps {
        /// Agent address (e.g. 127.0.0.1:9876)
        #[arg(short, long)]
        addr: SocketAddr,
    },
    /// Call a capability on a connected agent
    Call {
        #[arg(short, long)]
        addr: SocketAddr,
        /// Capability name (e.g. ui.navigate)
        capability: String,
        /// JSON params (e.g. '{"page":"settings"}')
        #[arg(default_value = "null")]
        params: String,
    },
    /// Interactive REPL session with an agent
    Repl {
        #[arg(short, long)]
        addr: SocketAddr,
    },
    /// Run a scripted demo against an agent
    Demo {
        #[arg(short, long, default_value = "127.0.0.1:9876")]
        addr: SocketAddr,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "remo_host=info".into()),
        )
        .init();

    let cli = Cli::parse();

    match cli.command {
        Commands::Caps { addr } => {
            let session = DeviceSession::connect(addr).await?;
            println!("Connected (protocol v{})", session.peer_version);
            println!();

            let caps = session.list_capabilities().await?;
            println!("Capabilities ({}):", caps.len());
            for cap in &caps {
                println!("  {:<24} {}", cap.name, cap.description);
            }
        }
        Commands::Call {
            addr,
            capability,
            params,
        } => {
            let params: serde_json::Value = serde_json::from_str(&params)?;
            let session = DeviceSession::connect(addr).await?;
            let result = session.call(&capability, params).await?;
            println!("{}", serde_json::to_string_pretty(&result)?);
        }
        Commands::Repl { addr } => {
            run_repl(addr).await?;
        }
        Commands::Demo { addr } => {
            run_demo(addr).await?;
        }
    }

    Ok(())
}

async fn run_repl(addr: SocketAddr) -> Result<()> {
    let session = DeviceSession::connect(addr).await?;
    println!("Connected (protocol v{})", session.peer_version);
    println!("Type <capability> <json_params> or 'quit'");
    println!();

    let stdin = tokio::io::stdin();
    let reader = tokio::io::BufReader::new(stdin);
    let mut lines = tokio::io::AsyncBufReadExt::lines(reader);

    while let Some(line) = lines.next_line().await? {
        let line = line.trim().to_string();
        if line.is_empty() {
            continue;
        }
        if line == "quit" || line == "exit" {
            break;
        }

        let (cap, params_str) = match line.split_once(' ') {
            Some((c, p)) => (c.to_string(), p.to_string()),
            None => (line, "null".to_string()),
        };

        let params: serde_json::Value = match serde_json::from_str(&params_str) {
            Ok(v) => v,
            Err(e) => {
                eprintln!("invalid JSON: {e}");
                continue;
            }
        };

        match session.call(&cap, params).await {
            Ok(data) => {
                println!("{}", serde_json::to_string_pretty(&data)?);
            }
            Err(e) => {
                eprintln!("error: {e}");
            }
        }
    }

    Ok(())
}

async fn run_demo(addr: SocketAddr) -> Result<()> {
    let session = DeviceSession::connect(addr).await?;
    println!("=== Remo Demo ===");
    println!("Connected to agent at {} (protocol v{})", addr, session.peer_version);
    println!();

    // 1. List capabilities
    println!("--- Listing capabilities ---");
    let caps = session.list_capabilities().await?;
    for cap in &caps {
        println!("  {:<24} {}", cap.name, cap.description);
    }
    println!();

    // 2. Ping
    println!("--- Ping ---");
    let pong = session.call("_ping", serde_json::json!(null)).await?;
    println!("  {}", pong);
    println!();

    // 3. Navigate
    println!("--- Navigate to 'settings' ---");
    let nav = session
        .call("ui.navigate", serde_json::json!({"page": "settings"}))
        .await?;
    println!("  {}", serde_json::to_string_pretty(&nav)?);
    println!();

    // 4. Get current page
    println!("--- Current page ---");
    let page = session.call("ui.current_page", serde_json::json!(null)).await?;
    println!("  {}", serde_json::to_string_pretty(&page)?);
    println!();

    // 5. Store operations
    println!("--- Store: list ---");
    let store = session.call("store.list", serde_json::json!(null)).await?;
    println!("  {}", serde_json::to_string_pretty(&store)?);
    println!();

    println!("--- Store: get 'user_name' ---");
    let val = session
        .call("store.get", serde_json::json!({"key": "user_name"}))
        .await?;
    println!("  {}", serde_json::to_string_pretty(&val)?);
    println!();

    println!("--- Store: set 'user_name' = 'Bob' ---");
    let set = session
        .call(
            "store.set",
            serde_json::json!({"key": "user_name", "value": "Bob"}),
        )
        .await?;
    println!("  {}", serde_json::to_string_pretty(&set)?);
    println!();

    println!("--- Store: get 'user_name' (after set) ---");
    let val2 = session
        .call("store.get", serde_json::json!({"key": "user_name"}))
        .await?;
    println!("  {}", serde_json::to_string_pretty(&val2)?);
    println!();

    // 6. View hierarchy
    println!("--- View hierarchy ---");
    let tree = session.call("ui.inspect", serde_json::json!(null)).await?;
    println!("  {}", serde_json::to_string_pretty(&tree)?);
    println!();

    // 7. Navigate back
    println!("--- Navigate to 'home' ---");
    let nav2 = session
        .call("ui.navigate", serde_json::json!({"page": "home"}))
        .await?;
    println!("  {}", serde_json::to_string_pretty(&nav2)?);
    println!();

    // 8. Runtime classes
    println!("--- ObjC runtime classes ---");
    let classes = session
        .call("runtime.classes", serde_json::json!(null))
        .await?;
    println!("  {}", serde_json::to_string_pretty(&classes)?);
    println!();

    println!("=== Demo complete ===");
    Ok(())
}
