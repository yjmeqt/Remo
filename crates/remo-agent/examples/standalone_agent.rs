use std::sync::Arc;

use anyhow::Result;
use remo_agent::server::AgentServer;
use remo_agent::handler::register_builtins;
use remo_agent::registry::CapabilityRegistry;
use remo_objc::MockBridge;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "remo_agent=info".into()),
        )
        .init();

    let port = std::env::args()
        .nth(1)
        .and_then(|s| s.parse::<u16>().ok())
        .unwrap_or(9876);

    let bridge = Arc::new(MockBridge::new());

    let mut registry = CapabilityRegistry::new();
    register_builtins(&mut registry, bridge);

    // Extra demo-only capability
    registry.register("echo", "Echo params back (demo)", |params| async move {
        Ok(params)
    });

    let addr = format!("127.0.0.1:{port}");
    let server = AgentServer::bind(&addr, registry).await?;
    println!("Remo agent listening on {}", server.local_addr());
    println!("Press Ctrl+C to stop.");

    server.run().await?;
    Ok(())
}
