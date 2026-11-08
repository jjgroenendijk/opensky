public import OpenSkyFormatsESM

/// What the world adapters use of `FaceMorphCoordinator`.
public protocol FaceMorphPort: AnyObject {
    func clearEmotion(on actor: FormID)
    func showEmotion(
        _ emotion: TopicInfo.Response.Emotion,
        value: UInt32,
        on actor: FormID,
        now: Float,
        seconds: Float?
    )
    func tick(now: Float)
}

/// The default arguments a protocol requirement cannot carry.
extension FaceMorphPort {
    public func showEmotion(
        _ emotion: TopicInfo.Response.Emotion,
        value: UInt32,
        on actor: FormID,
        now: Float
    ) {
        showEmotion(emotion, value: value, on: actor, now: now, seconds: nil)
    }
}
