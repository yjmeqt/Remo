use remo_core::types::ViewNode;

/// Low-level ObjC runtime operations.
///
/// On iOS this wraps libobjc FFI; on other platforms it provides stubs
/// for compile-time compatibility and testing.
pub struct ObjcRuntime;

impl ObjcRuntime {
    pub fn new() -> Self {
        Self
    }

    /// List all registered ObjC classes in the current process.
    #[cfg(target_os = "ios")]
    pub fn list_classes(&self) -> Vec<String> {
        // Real implementation uses objc_getClassList / class_getName
        unimplemented!("requires iOS runtime")
    }

    #[cfg(not(target_os = "ios"))]
    pub fn list_classes(&self) -> Vec<String> {
        vec![
            "UIViewController".into(),
            "UINavigationController".into(),
            "UIView".into(),
            "UILabel".into(),
            "UIButton".into(),
            "UITextField".into(),
            "UITableView".into(),
        ]
    }

    /// Send an ObjC message (selector) to an object at the given pointer address.
    #[cfg(target_os = "ios")]
    pub fn send_message(
        &self,
        _target_addr: usize,
        _selector: &str,
        _args: &[serde_json::Value],
    ) -> Result<serde_json::Value, String> {
        unimplemented!("requires iOS runtime")
    }

    #[cfg(not(target_os = "ios"))]
    pub fn send_message(
        &self,
        target_addr: usize,
        selector: &str,
        _args: &[serde_json::Value],
    ) -> Result<serde_json::Value, String> {
        tracing::info!(
            "mock send_message: 0x{:x} -[{selector}]",
            target_addr
        );
        Ok(serde_json::json!({ "mock": true, "selector": selector }))
    }

    /// Walk the UIWindow key-window view hierarchy and return a tree.
    #[cfg(target_os = "ios")]
    pub fn capture_view_hierarchy(&self) -> Result<ViewNode, String> {
        unimplemented!("requires iOS runtime")
    }

    #[cfg(not(target_os = "ios"))]
    pub fn capture_view_hierarchy(&self) -> Result<ViewNode, String> {
        use remo_core::types::Rect;
        Ok(ViewNode {
            class_name: "UIWindow".into(),
            address: "0x7fa000001".into(),
            frame: Rect { x: 0.0, y: 0.0, width: 390.0, height: 844.0 },
            properties: serde_json::Map::new(),
            children: vec![
                ViewNode {
                    class_name: "UINavigationController".into(),
                    address: "0x7fa000002".into(),
                    frame: Rect { x: 0.0, y: 0.0, width: 390.0, height: 844.0 },
                    properties: serde_json::Map::new(),
                    children: vec![
                        ViewNode {
                            class_name: "HomeViewController".into(),
                            address: "0x7fa000003".into(),
                            frame: Rect { x: 0.0, y: 0.0, width: 390.0, height: 844.0 },
                            properties: {
                                let mut m = serde_json::Map::new();
                                m.insert("title".into(), serde_json::json!("Home"));
                                m
                            },
                            children: vec![
                                ViewNode::new(
                                    "UILabel",
                                    "0x7fa000010",
                                    Rect { x: 20.0, y: 100.0, width: 350.0, height: 30.0 },
                                ),
                                ViewNode::new(
                                    "UIButton",
                                    "0x7fa000011",
                                    Rect { x: 20.0, y: 150.0, width: 150.0, height: 44.0 },
                                ),
                                ViewNode::new(
                                    "UITextField",
                                    "0x7fa000012",
                                    Rect { x: 20.0, y: 210.0, width: 350.0, height: 44.0 },
                                ),
                            ],
                        },
                    ],
                },
            ],
        })
    }
}

impl Default for ObjcRuntime {
    fn default() -> Self {
        Self::new()
    }
}
