//! Integration test: register a service, browse for it, verify it resolves.
//!
//! Requires macOS (dns_sd is an Apple system API).

use remo_bonjour::{BrowseEvent, ServiceBrowser, ServiceRegistration, TxtRecord, SERVICE_TYPE};
use tokio::time::{timeout, Duration};

#[tokio::test]
async fn register_and_discover() {
    let port = 19_930_u16;

    let mut txt = TxtRecord::new();
    txt.set("test_key", "test_value").unwrap();

    let _reg =
        ServiceRegistration::register(SERVICE_TYPE, port, Some("RemoTest"), Some(&txt)).unwrap();

    // Give dns_sd a moment to propagate.
    tokio::time::sleep(Duration::from_millis(500)).await;

    let (_browser, mut rx) = ServiceBrowser::browse(SERVICE_TYPE).unwrap();

    let event = timeout(Duration::from_secs(5), async {
        while let Some(event) = rx.recv().await {
            match &event {
                BrowseEvent::Found(info) if info.name == "RemoTest" => return event,
                _ => continue,
            }
        }
        panic!("channel closed before RemoTest was discovered");
    })
    .await
    .expect("timed out waiting for RemoTest browse event");

    match event {
        BrowseEvent::Found(info) => {
            assert_eq!(info.name, "RemoTest");
            assert_eq!(info.port, port);
            assert!(!info.host.is_empty());
        }
        BrowseEvent::Lost { .. } => panic!("expected Found event, got Lost"),
    }
}
