use thiserror::Error;

#[derive(Error, Debug)]
pub enum RemoError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Protocol error: {0}")]
    Protocol(String),

    #[error("Serialization error: {0}")]
    Serialization(String),

    #[error("Capability not found: {0}")]
    CapabilityNotFound(String),

    #[error("Device not found: {0}")]
    DeviceNotFound(String),

    #[error("Connection refused")]
    ConnectionRefused,

    #[error("Timeout")]
    Timeout,

    #[error("ObjC runtime error: {0}")]
    ObjcRuntime(String),

    #[error("Handshake failed: {0}")]
    HandshakeFailed(String),

    #[error("Channel closed")]
    ChannelClosed,
}
