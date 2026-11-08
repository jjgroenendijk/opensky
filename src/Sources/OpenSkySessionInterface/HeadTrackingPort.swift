public import OpenSkyFormatsESM

/// What the world adapters use of `HeadTrackingCoordinator`.
public protocol HeadTrackingPort: AnyObject {
    func setHeadTracking(_ enabled: Bool, for actor: ReferenceKey)
    func setLookTarget(
        _ target: ReferenceKey?,
        for actor: ReferenceKey,
        seconds: Float?,
        dialogue: Bool
    )
    var isEnabled: Bool { get set }
    func tick(deltaTime: Float)
}

/// The default arguments a protocol requirement cannot carry.
extension HeadTrackingPort {
    public func setLookTarget(_ target: ReferenceKey?, for actor: ReferenceKey, dialogue: Bool) {
        setLookTarget(target, for: actor, seconds: nil, dialogue: dialogue)
    }

    public func setLookTarget(_ target: ReferenceKey?, for actor: ReferenceKey, seconds: Float?) {
        setLookTarget(target, for: actor, seconds: seconds, dialogue: false)
    }

    public func setLookTarget(_ target: ReferenceKey?, for actor: ReferenceKey) {
        setLookTarget(target, for: actor, seconds: nil, dialogue: false)
    }
}
