public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `PackageCoordinator`.
public protocol PackagePort: AnyObject {
    associatedtype PackageOverrideExecution: PackageOverrideExecutionPort
    associatedtype ActorPackageRuntime: ActorPackageRuntimePort
    func advance(by delta: Float)
    func advanceBumps(_ contacts: [BumpContact], now: Double) -> [BumpCommand]
    func clearOverride(owner: PackageOverrideOwner, actor: ReferenceKey)
    func evaluate(_ actor: ReferenceKey)
    func flightArrived(_ actor: ReferenceKey)
    func flightTarget(of actor: ReferenceKey) -> PackageFlightTarget?
    func followRunSlowdown(for actor: ReferenceKey) -> FollowSettings?
    func holdCommanded(_ actor: ReferenceKey)
    func ignoresCombat(_ actor: ReferenceKey) -> Bool
    func movementSettled(actor: ReferenceKey, reason: NPCMovementSettleReason)
    func packageLocation(of actor: ReferenceKey) -> SIMD3<Float>?
    /// A new game: every persistent actor goes to the place of its package for the hour.
    func placeActorsAtPackagePlaces()
    func readout(for actor: ReferenceKey) -> PackageActorReadout?
    func readouts() -> [PackageActorReadout]
    /// The last off-screen update of an actor no loaded cell holds, as one line.
    func offscreenReadout(for actor: ReferenceKey) -> String?
    /// The AI process levels in numbers: the actors on each level, the Low pass, the budget.
    var processReadout: [String: Double] { get }
    func recordMove(_ result: NPCMoveCommandResult, for actor: ReferenceKey)
    func releaseCommanded(_ actor: ReferenceKey)
    func resume(_ actor: ReferenceKey)
    func runOverride(_ override: PackageOverride, actor: ReferenceKey) -> PackageOverrideProgress
    var runtime: ActorPackageRuntime? { get }
    func suspend(_ actor: ReferenceKey)
    func isSuspended(_ actor: ReferenceKey) -> Bool
    func template(of package: FormID) -> FormID?
    var trespassWarnings: [ReferenceKey: Int] { get }
    func sandboxArea(of actor: ReferenceKey) -> IdleSearchArea?
    func allowsSandboxConversation(_ actor: ReferenceKey) -> Bool

    var executions: [ReferenceKey: PackageOverrideExecution] { get }
    var lastMoves: [ReferenceKey: NPCMoveCommandResult] { get }
}

/// The default arguments a protocol requirement cannot carry.
extension PackagePort {}
