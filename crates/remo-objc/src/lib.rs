#![allow(unsafe_code)]

pub mod device_info;
pub mod main_thread;
pub mod screenshot;
pub mod view_tree;

pub use device_info::{get_app_info, get_device_info, AppInfo, DeviceInfo};
pub use main_thread::{is_main_thread, run_on_main_sync};
pub use screenshot::{capture_screenshot, ScreenshotResult};
pub use view_tree::{snapshot_view_tree, Frame, ViewNode};
