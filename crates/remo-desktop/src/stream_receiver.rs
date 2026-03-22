use remo_protocol::StreamFrame;
use tokio::sync::broadcast;

/// Cloneable receiver for stream frames.
pub struct StreamReceiver {
    rx: broadcast::Receiver<StreamFrame>,
}

impl StreamReceiver {
    pub fn new(rx: broadcast::Receiver<StreamFrame>) -> Self {
        Self { rx }
    }

    /// Receive the next frame. Returns `None` when the stream ends.
    pub async fn next_frame(&mut self) -> Option<StreamFrame> {
        loop {
            match self.rx.recv().await {
                Ok(frame) => return Some(frame),
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    tracing::warn!(skipped = n, "stream receiver lagged, frames dropped");
                    continue;
                }
                Err(broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn receive_frame() {
        let (tx, rx) = broadcast::channel(16);
        let mut receiver = StreamReceiver::new(rx);

        let frame = StreamFrame {
            stream_id: 1,
            sequence: 42,
            timestamp_us: 1000,
            flags: 0,
            data: vec![0xDE, 0xAD],
        };

        tx.send(frame.clone()).unwrap();

        let got = receiver.next_frame().await.unwrap();
        assert_eq!(got.stream_id, 1);
        assert_eq!(got.sequence, 42);
        assert_eq!(got.timestamp_us, 1000);
        assert_eq!(got.data, vec![0xDE, 0xAD]);
    }

    #[tokio::test]
    async fn closed_returns_none() {
        let (tx, rx) = broadcast::channel::<StreamFrame>(16);
        let mut receiver = StreamReceiver::new(rx);

        drop(tx);

        assert!(receiver.next_frame().await.is_none());
    }
}
