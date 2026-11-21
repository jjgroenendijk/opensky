public import OpenSkyConditions
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM

/// One change to the world outside the social pass.
nonisolated public enum SocialEventCommand: Equatable, Sendable {
    /// Sends the event to the story manager, which fills in its location.
    case reportStoryEvent(StoryEventData)
    /// The actor says a line of the topic subtype, such as `NOTI` (NoticeCorpse) or
    /// `OBCO` (ObserveCombat), facing `lookAt`.
    case say(FourCC, ReferenceKey, lookAt: ReferenceKey?)
    /// Turns the actor's head to the target; nil gives the head back.
    case look(ReferenceKey, at: ReferenceKey?)
    /// The actor's package stops moving it, as a short wait package does.
    case hold(ReferenceKey)
    /// The actor's package runs again.
    case release(ReferenceKey)
    /// The actor walks to the point. The actor is held while it walks.
    case walk(ReferenceKey, to: SIMD3<Float>)
    /// The actor stops its walk, and its package runs again.
    case stopWalking(ReferenceKey)
    /// The actor leaves its seat or bed.
    case standUp(ReferenceKey)
    /// The actor turns its body to the point. Sent each pass until the reason ends.
    case face(ReferenceKey, toward: SIMD3<Float>)
    /// The actor puts its weapon away.
    case sheathe(ReferenceKey)
}
