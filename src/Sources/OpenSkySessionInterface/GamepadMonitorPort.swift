public import OpenSkyMenusInterface

/// What the world adapters use of `GamepadMonitor`.
public protocol GamepadMonitorPort: AnyObject {
    var simulatedCount: Int { get set }
    var simulatedPress: Set<GamepadButton> { get set }
    /// Gamepads reported to the movies now: real ones, else the simulated count.
    var count: Int { get }
    /// The last gameplay user event a gamepad pressed, such as `Jump`.
    var lastUserEvent: String? { get }
}
