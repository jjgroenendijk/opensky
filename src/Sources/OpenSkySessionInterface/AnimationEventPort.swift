public import OpenSkyBehavior
public import OpenSkyFormatsESM

/// What the world adapters use of `AnimationEventCoordinator`.
public protocol AnimationEventPort: AnyObject {
    @discardableResult func handle(
        _ name: String,
        from source: ReferenceKey,
        reachesEffectGraphs: Bool
    ) -> AnimationEventAction?
}

/// The default arguments a protocol requirement cannot carry.
extension AnimationEventPort {
    @discardableResult public func handle(
        _ name: String,
        from source: ReferenceKey
    ) -> AnimationEventAction? {
        handle(name, from: source, reachesEffectGraphs: true)
    }
}
