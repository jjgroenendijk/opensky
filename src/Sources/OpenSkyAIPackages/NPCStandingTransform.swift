public import OpenSkyWorldState

/// Where an actor stands, from its movement or from the world state.
public struct NPCStandingTransform {
    let movement: NPCMovementRuntime

    public init(movement: NPCMovementRuntime) {
        self.movement = movement
    }

    /// Where an actor stands: its movement pose, else the pose a cell build draws
    /// from `snapshot`, which is the saved transform when one exists, then the record.
    public func standingTransform(
        of entry: RuntimeReferenceEntry,
        in snapshot: @autoclosure () -> WorldStateSnapshot
    ) -> ReferenceTransformOverride {
        movement.transform(for: entry.key) ?? snapshot().resolvedState(for: entry).transform
    }
}
