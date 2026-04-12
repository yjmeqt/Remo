#if DEBUG
import RemoSwift

func _symbolProbe() async {
    _ = _RemoRuntime.self
    _ = _RemoRuntime.unregister("navigate")
}
#endif
