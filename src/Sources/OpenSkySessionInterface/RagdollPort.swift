public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyPhysics

/// What the world adapters use of `RagdollCoordinator`.
public protocol RagdollPort: AnyObject {
    func advancePlayerDeath(by delta: Float, health: PlayerHealthSample) -> [PlayerDeathCommand]
    associatedtype KnockdownTracker: KnockdownTrackerPort
    associatedtype PlayerDeath: PlayerDeathPort
    associatedtype RagdollRuntime: RagdollRuntimePort
    func advance(events: [String], controls: RagdollGraphControls, delta: Float) -> [RagdollCommand]
    var deathSettings: DeathSettings { get }
    @discardableResult func dismember(_ key: ReferenceKey) -> Bool
    func dropPlayerBody()
    @discardableResult func knockDown(
        _ key: ReferenceKey,
        from source: SIMD3<Float>,
        magnitude: Float,
        downTime: Float
    ) -> Bool
    var knockdowns: KnockdownTracker { get }
    func noteHit(_ hit: CombatHitRecord, on key: ReferenceKey)
    var playerDeath: PlayerDeath { get set }
    func publishPoses() -> [RagdollCommand]
    func resetPlayerDeath()
    var runtime: RagdollRuntime? { get }
    @discardableResult func searchCorpse(_ key: ReferenceKey) -> Bool
    @discardableResult func searchNearestCorpse() -> Bool
    var severedHeads: [ReferenceKey: SeveredHead] { get }
}
