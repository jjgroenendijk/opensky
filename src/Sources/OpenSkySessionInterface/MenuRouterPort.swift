/// What the world adapters use of `MenuRouter`.
public protocol MenuRouterPort: AnyObject {
    var gamepads: any GamepadMonitorPort { get }
}
