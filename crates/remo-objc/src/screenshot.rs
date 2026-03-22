//! Screenshot capture via UIKit rendering.
//!
//! Uses `UIGraphicsBeginImageContextWithOptions` + `drawViewHierarchyInRect:afterScreenUpdates:`
//! to capture the key window, then encodes as JPEG or PNG.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScreenshotResult {
    pub bytes: Vec<u8>,
    pub format: String,
    pub width: f64,
    pub height: f64,
    pub scale: f64,
}

#[cfg(all(target_vendor = "apple", feature = "uikit"))]
mod apple {
    use super::*;
    use objc2::runtime::AnyObject;
    use objc2::{msg_send, MainThreadMarker};
    use objc2_ui_kit::UIApplication;

    type CGFloat = f64;

    #[repr(C)]
    struct CGSize {
        width: CGFloat,
        height: CGFloat,
    }

    extern "C" {
        fn UIGraphicsBeginImageContextWithOptions(size: CGSize, opaque: bool, scale: CGFloat);
        fn UIGraphicsGetImageFromCurrentImageContext() -> *mut AnyObject;
        fn UIGraphicsEndImageContext();
        fn UIImagePNGRepresentation(image: *mut AnyObject) -> *mut AnyObject;
        fn UIImageJPEGRepresentation(image: *mut AnyObject, quality: CGFloat) -> *mut AnyObject;
    }

    /// Capture a screenshot of the key window.
    ///
    /// # Safety
    /// Must be called on the main thread (UIKit requirement).
    pub unsafe fn capture(format: &str, quality: f64) -> Option<ScreenshotResult> {
        let mtm = MainThreadMarker::new_unchecked();
        let app = UIApplication::sharedApplication(mtm);
        #[allow(deprecated)]
        let windows = app.windows();
        let key_window = windows.iter().find(|w| w.isKeyWindow())?;

        let bounds: objc2_foundation::NSRect = msg_send![&*key_window, bounds];
        let screen: *mut AnyObject = msg_send![&*key_window, screen];
        let scale: f64 = msg_send![screen, scale];

        let size = CGSize {
            width: bounds.size.width,
            height: bounds.size.height,
        };

        UIGraphicsBeginImageContextWithOptions(size, false, scale);

        let after_updates: bool = true;
        let _success: bool = msg_send![
            &*key_window,
            drawViewHierarchyInRect: bounds,
            afterScreenUpdates: after_updates
        ];

        let image: *mut AnyObject = UIGraphicsGetImageFromCurrentImageContext();
        if image.is_null() {
            UIGraphicsEndImageContext();
            return None;
        }

        let data: *mut AnyObject = if format == "png" {
            UIImagePNGRepresentation(image)
        } else {
            UIImageJPEGRepresentation(image, quality)
        };

        UIGraphicsEndImageContext();

        if data.is_null() {
            return None;
        }

        // NSData: get raw bytes via -[NSData bytes] and -[NSData length]
        let ptr: *const u8 = msg_send![data, bytes];
        let len: usize = msg_send![data, length];
        let bytes = std::slice::from_raw_parts(ptr, len).to_vec();

        Some(ScreenshotResult {
            bytes,
            format: if format == "png" {
                "png".into()
            } else {
                "jpeg".into()
            },
            width: bounds.size.width,
            height: bounds.size.height,
            scale,
        })
    }
}

#[cfg(not(all(target_vendor = "apple", feature = "uikit")))]
mod apple {
    use super::*;

    pub unsafe fn capture(_format: &str, _quality: f64) -> Option<ScreenshotResult> {
        tracing::warn!("capture_screenshot called on non-Apple target, returning None");
        None
    }
}

/// Capture a screenshot of the app's key window.
///
/// # Safety
/// On iOS, must be called from the main thread.
pub unsafe fn capture_screenshot(format: &str, quality: f64) -> Option<ScreenshotResult> {
    apple::capture(format, quality)
}
