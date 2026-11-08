public import OpenSkyMenusInterface

/// What the world adapters use of `RaceMenuCoordinator`.
public protocol RaceMenuPort: AnyObject {
    func tick(now: Double)
    var isOpen: Bool { get }
    var isZoomedIn: Bool { get }
    @discardableResult func open(limited: Bool) -> Bool
    func route(_ event: MenuPointerEvent)
    func route(_ event: MenuInputEvent)
    var snapshot: RaceMenuSnapshot { get }
    func type(_ text: String) -> Bool
}
