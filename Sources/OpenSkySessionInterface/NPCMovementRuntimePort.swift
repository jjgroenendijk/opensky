public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `NPCMovementRuntime`.
public protocol NPCMovementRuntimePort {
    func hasRoom(for actor: ReferenceKey) -> Bool
    func motionFacts() -> [ReferenceKey: ReferenceMotionFacts]
}
