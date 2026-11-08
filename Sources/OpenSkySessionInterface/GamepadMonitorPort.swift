public import OpenSkyMenusInterface

/// What the world adapters use of `GamepadMonitor`.
public protocol GamepadMonitorPort: AnyObject {
    var simulatedCount: Int { get set }
    var simulatedPress: Set<GamepadButton> { get set }
}
