use std::net::SocketAddr;
use std::pin::Pin;
use std::task::{Context, Poll};

use futures::{SinkExt, StreamExt};
use remo_protocol::{Message, RemoCodec};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::net::TcpStream;
use tokio_util::codec::Framed;

#[derive(Debug, thiserror::Error)]
pub enum TransportError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),

    #[error("codec: {0}")]
    Codec(#[from] remo_protocol::codec::CodecError),

    #[error("connection closed")]
    Closed,
}

/// Internal stream abstraction supporting TCP and Unix sockets.
enum IoStream {
    Tcp(TcpStream),
    #[cfg(unix)]
    Unix(tokio::net::UnixStream),
}

impl AsyncRead for IoStream {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        match self.get_mut() {
            IoStream::Tcp(s) => Pin::new(s).poll_read(cx, buf),
            #[cfg(unix)]
            IoStream::Unix(s) => Pin::new(s).poll_read(cx, buf),
        }
    }
}

impl AsyncWrite for IoStream {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        match self.get_mut() {
            IoStream::Tcp(s) => Pin::new(s).poll_write(cx, buf),
            #[cfg(unix)]
            IoStream::Unix(s) => Pin::new(s).poll_write(cx, buf),
        }
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        match self.get_mut() {
            IoStream::Tcp(s) => Pin::new(s).poll_flush(cx),
            #[cfg(unix)]
            IoStream::Unix(s) => Pin::new(s).poll_flush(cx),
        }
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        match self.get_mut() {
            IoStream::Tcp(s) => Pin::new(s).poll_shutdown(cx),
            #[cfg(unix)]
            IoStream::Unix(s) => Pin::new(s).poll_shutdown(cx),
        }
    }
}

/// A bidirectional message connection over TCP or Unix socket.
pub struct Connection {
    framed: Framed<IoStream, RemoCodec>,
    peer: SocketAddr,
}

impl Connection {
    /// Wrap an already-connected `TcpStream`.
    pub fn new(stream: TcpStream) -> Result<Self, TransportError> {
        let peer = stream.peer_addr()?;
        stream.set_nodelay(true)?;
        let framed = Framed::new(IoStream::Tcp(stream), RemoCodec);
        Ok(Self { framed, peer })
    }

    /// Wrap a Unix stream (e.g. a usbmuxd tunnel).
    ///
    /// The `label` address is used for logging since Unix streams
    /// don't have a meaningful socket address.
    #[cfg(unix)]
    pub fn from_unix_stream(stream: tokio::net::UnixStream, label: SocketAddr) -> Self {
        let framed = Framed::new(IoStream::Unix(stream), RemoCodec);
        Self {
            framed,
            peer: label,
        }
    }

    /// Connect to a remote address.
    pub async fn connect(addr: SocketAddr) -> Result<Self, TransportError> {
        let stream = TcpStream::connect(addr).await?;
        Self::new(stream)
    }

    /// Send a message.
    pub async fn send(&mut self, msg: Message) -> Result<(), TransportError> {
        self.framed.send(msg).await?;
        Ok(())
    }

    /// Receive the next message, or `None` if the connection is closed.
    pub async fn recv(&mut self) -> Result<Option<Message>, TransportError> {
        match self.framed.next().await {
            Some(Ok(msg)) => Ok(Some(msg)),
            Some(Err(e)) => Err(TransportError::Codec(e)),
            None => Ok(None),
        }
    }

    /// Peer address.
    pub fn peer_addr(&self) -> SocketAddr {
        self.peer
    }

    /// Split into independent read and write halves for concurrent use.
    pub fn split(self) -> (ReadHalf, WriteHalf) {
        let (sink, stream) = self.framed.split();
        (
            ReadHalf {
                stream,
                peer: self.peer,
            },
            WriteHalf {
                sink,
                peer: self.peer,
            },
        )
    }
}

// Type aliases for the split halves.
type FramedStream = futures::stream::SplitStream<Framed<IoStream, RemoCodec>>;
type FramedSink = futures::stream::SplitSink<Framed<IoStream, RemoCodec>, Message>;

/// Read half of a split connection.
pub struct ReadHalf {
    stream: FramedStream,
    peer: SocketAddr,
}

impl ReadHalf {
    pub async fn recv(&mut self) -> Result<Option<Message>, TransportError> {
        match self.stream.next().await {
            Some(Ok(msg)) => Ok(Some(msg)),
            Some(Err(e)) => Err(TransportError::Codec(e)),
            None => Ok(None),
        }
    }

    pub fn peer_addr(&self) -> SocketAddr {
        self.peer
    }
}

/// Write half of a split connection.
pub struct WriteHalf {
    sink: FramedSink,
    peer: SocketAddr,
}

impl WriteHalf {
    pub async fn send(&mut self, msg: Message) -> Result<(), TransportError> {
        self.sink.send(msg).await?;
        Ok(())
    }

    pub fn peer_addr(&self) -> SocketAddr {
        self.peer
    }
}
