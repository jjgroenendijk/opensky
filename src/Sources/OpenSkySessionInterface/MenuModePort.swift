public import OpenSkyMenusInterface

/// What the world adapters use of `MenuModeController`.
public protocol MenuModePort: AnyObject, MenuInputRouting {
    @discardableResult func dismiss(_ identifier: MenuIdentifier) -> Bool
    var isMenuMode: Bool { get }
    var isWorldSimPaused: Bool { get }
    @discardableResult func present(_ identifier: MenuIdentifier, policy: MenuWorldPolicy) -> Bool
    @discardableResult func routeMenuPointer(_ event: MenuPointerEvent) -> Bool
    var stack: MenuStack { get }
    var topMenu: MenuIdentifier? { get }
    var inputConsumer: (any MenuInputConsumer)? { get set }
}

/// The default arguments a protocol requirement cannot carry.
extension MenuModePort {
    @discardableResult public func present(_ identifier: MenuIdentifier) -> Bool {
        present(identifier, policy: .pausesWorld)
    }
}
