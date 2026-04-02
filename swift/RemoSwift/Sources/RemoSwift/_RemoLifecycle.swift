#if DEBUG
import UIKit
import ObjectiveC

/// Internal UIKit lifecycle manager for `#remo("name", scopedTo: self)` expansions.
///
/// Swizzles `UIViewController.viewDidDisappear(_:)` once per process lifetime.
/// Uses associated objects to track registered capability names per VC instance.
/// When a VC disappears, all its tracked capabilities are unregistered.
internal enum _RemoLifecycle {
    private static var _swizzled = false
    private static let _lock = NSLock()

    // Key for objc associated object storing [String] of registered capability names.
    private static var _namesKey: UInt8 = 0

    /// Register a capability and associate it with `owner`'s disappear lifecycle.
    ///
    /// Called by the `#remo("name", scopedTo: self)` macro expansion.
    static func registerScoped(
        owner: UIViewController,
        name: String,
        handler: @escaping ([String: Any]) -> [String: Any]
    ) {
        _swizzleOnce()
        var names = objc_getAssociatedObject(owner, &_namesKey) as? [String] ?? []
        if !names.contains(name) {
            names.append(name)
        }
        objc_setAssociatedObject(owner, &_namesKey, names, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        Remo.register(name, handler: handler)
    }

    private static func _swizzleOnce() {
        _lock.lock()
        defer { _lock.unlock() }
        guard !_swizzled else { return }
        _swizzled = true

        let cls = UIViewController.self
        let original = #selector(UIViewController.viewDidDisappear(_:))
        let swizzled = #selector(UIViewController._remo_viewDidDisappear(_:))
        guard
            let originalMethod = class_getInstanceMethod(cls, original),
            let swizzledMethod = class_getInstanceMethod(cls, swizzled)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension UIViewController {
    @objc func _remo_viewDidDisappear(_ animated: Bool) {
        // After swizzling, calling this invokes the original viewDidDisappear.
        _remo_viewDidDisappear(animated)
        guard let names = objc_getAssociatedObject(self, &_RemoLifecycle._namesKey) as? [String],
              !names.isEmpty else { return }
        names.forEach { Remo.unregister($0) }
        objc_setAssociatedObject(self, &_RemoLifecycle._namesKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
#endif
