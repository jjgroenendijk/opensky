public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldInterface

/// What the world adapters use of `NPCMovementRuntime`.
public protocol NPCMovementRuntimePort {
    func hasRoom(for actor: ReferenceKey) -> Bool
    func motionFacts() -> [ReferenceKey: ReferenceMotionFacts]
    /// The actors whose mover swims now.
    func swimmingActors() -> Set<ReferenceKey>
    /// The band `actor` walks in, or nil when it is not walking.
    func movementBand(of actor: ReferenceKey) -> UpdateBand?
}
