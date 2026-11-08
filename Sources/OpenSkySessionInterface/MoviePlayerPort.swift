public import OpenSkyMenusInterface

/// What the world adapters use of `MoviePlayerCoordinator`.
public protocol MoviePlayerPort: AnyObject {
    @discardableResult func play(
        _ request: MovieRequest,
        onEnd: @escaping (MovieOutcome) -> Void
    ) -> Bool
    var readout: MoviePlaybackReadout { get }
    @discardableResult func skip(force: Bool) -> Bool
    func tick(now: Double)

    func route(_ event: MenuInputEvent)
}

/// The default arguments a protocol requirement cannot carry.
extension MoviePlayerPort {
    @discardableResult public func skip() -> Bool {
        skip(force: false)
    }
}
