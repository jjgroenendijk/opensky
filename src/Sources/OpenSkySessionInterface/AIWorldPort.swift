public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyScriptingInterface
public import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What the world adapters use of `AIWorldAdapter`.
public protocol AIWorldPort: AnyObject, PapyrusFurnitureBridge {
    func activate(_ target: ReferenceKey, by actor: ReferenceKey) -> PackageActionResult
    func dismountPackageActor(_ rider: ReferenceKey)
    func furnitureActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>?
    func furnitureSeats(of furniture: ReferenceKey) -> [FurnitureSeat]?
    func isAIDisabled(_ actor: ReferenceKey) -> Bool
    func isWithin(_ location: Package.Location, actor: ReferenceKey) -> Bool
    func lightLevel(at position: SIMD3<Float>) -> Float
    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult
    func movePackageActor(_ move: PackageMove) -> PackageMoveResult
    func packageActorActivity(_ actor: ReferenceKey) -> PackageActorActivity
    func packageActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>?
    func packageConditionContext(clock: GameClock) -> ConditionContext
    func perceptionHasLineOfSight(from origin: SIMD3<Float>, to destination: SIMD3<Float>) -> Bool
    func stopPackageActor(_ actor: ReferenceKey)
}
