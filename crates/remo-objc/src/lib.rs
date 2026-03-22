#![allow(unsafe_code)]

pub mod device_info;
pub mod main_thread;
pub mod screen_capture;
pub mod screenshot;
pub mod video_encoder;
pub mod view_tree;

pub use device_info::{get_app_info, get_device_info, AppInfo, DeviceInfo};
pub use main_thread::{is_main_thread, run_on_main_sync};
pub use screen_capture::{capture_frame_to_pixel_buffer, get_screen_info, CaptureInfo};
pub use screenshot::{capture_screenshot, ScreenshotResult};
pub use video_encoder::{avcc_to_annex_b, EncodedFrame, EncoderConfig, H264Encoder};
pub use view_tree::{snapshot_view_tree, Frame, ViewNode};
