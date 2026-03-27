use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

use chrono::Utc;
use serde_json::Value;
use tokio::sync::broadcast;

use crate::types::DaemonEvent;

/// Central event distribution hub.
///
/// Events are stored in a bounded ring buffer for cursor-based polling and
/// simultaneously broadcast to real-time WebSocket subscribers.
pub struct EventBus {
    seq: AtomicU64,
    buffer: Mutex<VecDeque<DaemonEvent>>,
    capacity: usize,
    tx: broadcast::Sender<DaemonEvent>,
}

impl EventBus {
    /// Create a new `EventBus` with the given ring-buffer capacity.
    pub fn new(capacity: usize) -> Self {
        let (tx, _rx) = broadcast::channel(capacity.max(1));
        Self {
            seq: AtomicU64::new(0),
            buffer: Mutex::new(VecDeque::with_capacity(capacity)),
            capacity,
            tx,
        }
    }

    /// Emit a new event. Assigns a monotonically increasing sequence number and
    /// the current UTC timestamp, stores the event in the ring buffer (evicting
    /// the oldest entry when full), and broadcasts to all live subscribers.
    pub fn emit(&self, kind: &str, device: Option<String>, payload: Value) {
        let seq = self.seq.fetch_add(1, Ordering::SeqCst) + 1;
        let event = DaemonEvent {
            seq,
            timestamp: Utc::now(),
            kind: kind.to_string(),
            device,
            payload,
        };

        {
            let mut buf = self.buffer.lock().expect("event buffer poisoned");
            if buf.len() == self.capacity {
                buf.pop_front();
            }
            buf.push_back(event.clone());
        }

        // Ignore send errors — they just mean no active receivers.
        let _ = self.tx.send(event);
    }

    /// Return up to `limit` events whose `seq` is strictly greater than `cursor`.
    pub fn poll(&self, cursor: u64, limit: usize) -> Vec<DaemonEvent> {
        let buf = self.buffer.lock().expect("event buffer poisoned");
        buf.iter()
            .filter(|e| e.seq > cursor)
            .take(limit)
            .cloned()
            .collect()
    }

    /// Obtain a broadcast receiver for real-time event notifications.
    pub fn subscribe(&self) -> broadcast::Receiver<DaemonEvent> {
        self.tx.subscribe()
    }

    /// Return the sequence number of the oldest event still in the buffer,
    /// or `None` if the buffer is empty.
    pub fn earliest_cursor(&self) -> Option<u64> {
        let buf = self.buffer.lock().expect("event buffer poisoned");
        buf.front().map(|e| e.seq)
    }

    /// Return the latest sequence number that has been assigned (0 if no
    /// events have been emitted yet).
    pub fn latest_seq(&self) -> u64 {
        self.seq.load(Ordering::SeqCst)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn emit_assigns_sequential_ids() {
        let bus = EventBus::new(16);
        bus.emit("a", None, json!({}));
        bus.emit("b", None, json!({}));

        let events = bus.poll(0, 10);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].seq, 1);
        assert_eq!(events[1].seq, 2);
    }

    #[test]
    fn poll_returns_events_after_cursor() {
        let bus = EventBus::new(16);
        bus.emit("a", None, json!({}));
        bus.emit("b", None, json!({}));
        bus.emit("c", None, json!({}));

        let events = bus.poll(1, 10);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].seq, 2);
        assert_eq!(events[1].seq, 3);
    }

    #[test]
    fn ring_buffer_evicts_oldest() {
        let bus = EventBus::new(3);
        bus.emit("a", None, json!({}));
        bus.emit("b", None, json!({}));
        bus.emit("c", None, json!({}));
        bus.emit("d", None, json!({}));

        let events = bus.poll(0, 10);
        assert_eq!(events.len(), 3);
        // The first event (seq=1) should have been evicted.
        assert_eq!(events[0].seq, 2);
        assert_eq!(events[1].seq, 3);
        assert_eq!(events[2].seq, 4);
    }

    #[test]
    fn poll_with_expired_cursor_returns_all_available() {
        let bus = EventBus::new(2);
        bus.emit("a", None, json!({}));
        bus.emit("b", None, json!({}));
        bus.emit("c", None, json!({}));

        // cursor 0 is before any event, but the buffer only holds the last 2.
        let events = bus.poll(0, 10);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].seq, 2);
        assert_eq!(events[1].seq, 3);
    }

    #[tokio::test]
    async fn subscribe_receives_new_events() {
        let bus = EventBus::new(16);
        let mut rx = bus.subscribe();

        bus.emit("hello", Some("dev1".into()), json!({"x": 1}));

        let event = rx.recv().await.expect("should receive event");
        assert_eq!(event.kind, "hello");
        assert_eq!(event.device.as_deref(), Some("dev1"));
        assert_eq!(event.payload, json!({"x": 1}));
    }

    #[test]
    fn earliest_cursor_returns_none_when_empty() {
        let bus = EventBus::new(16);
        assert_eq!(bus.earliest_cursor(), None);
    }

    #[test]
    fn earliest_cursor_returns_first_seq() {
        let bus = EventBus::new(16);
        bus.emit("a", None, json!({}));
        bus.emit("b", None, json!({}));
        assert_eq!(bus.earliest_cursor(), Some(1));
    }
}
