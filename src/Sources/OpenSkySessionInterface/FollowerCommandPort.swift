public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `FollowerCommandCoordinator`.
public protocol FollowerCommandPort: AnyObject {
    func advanceUseKey(by delta: Float, isDown: Bool) -> FollowerUseKey?
    @discardableResult func cancel() -> Bool
    @discardableResult func command(_ target: FollowerCommandTarget?) -> FollowerCommandDecision?
    func favorEnded(_ follower: ReferenceKey)
    func favorStarted(_ follower: ReferenceKey)
    var isChoosing: Bool { get }
    var lastDecision: FollowerCommandDecision? { get }
    var lastOutcome: FollowerCommandOutcome? { get }
    var phase: FollowerCommandPhase { get }
    var settings: FollowerCommandSettings { get }
    func tick(_ delta: Float)
    func useKeyDown(on follower: ReferenceKey)
    func movementSettled(actor: ReferenceKey, reason: NPCMovementSettleReason)
}
