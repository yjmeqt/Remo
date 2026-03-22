pub mod codec;
pub mod message;

pub use codec::RemoCodec;
pub use message::{
    stream_flags, BinaryResponse, ErrorCode, Event, Message, MessageId, Request, Response,
    ResponseResult, StreamFrame,
};

/// Default port that remo-sdk listens on inside the iOS app.
pub const DEFAULT_PORT: u16 = 9930;
