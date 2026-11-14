public import OpenSkyMenusInterface

/// What the world adapters use of `TitleMenuCoordinator`.
public protocol TitleMenuPort: AnyObject {
    func close()
    var creditsShown: Bool { get }
    var isOpen: Bool { get }
    func load(_ slot: String, acceptingChangedContent: Bool)
    func route(_ event: MenuPointerEvent)
    func route(_ event: MenuInputEvent)
    var snapshot: TitleMenuSnapshot { get }
    func tick(now: Double)
}

/// The default arguments a protocol requirement cannot carry.
extension TitleMenuPort {
    public func load(_ slot: String) {
        load(slot, acceptingChangedContent: false)
    }
}
