// An ACHR's height can sit inside the road or floor it stands on. The game's character
// controller pushes the actor up out of the floor; a cell build lifts it the same way.
// See docs/engine/navigation.md#standing-height.

import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

nonisolated extension CellSceneBuilder {
    /// How far below a floor's top an actor's feet may be and still rise onto it. Half
    /// the capsule: a deeper floor is a roof or a bridge over the actor.
    static let actorFloorReach: Float = PlayerCapsule.standard.height / 2

    nonisolated static func standingOnFloors(
        _ actors: [CollectedActor],
        collision: StaticCollisionSet
    ) -> [CollectedActor] {
        guard !collision.shapes.isEmpty else { return actors }
        return actors.map { collected in
            let placement = collected.actor.placement
            guard
                let floor = Self.floorHeight(under: placement.position, collision: collision),
                floor > placement.position.z
            else { return collected }
            var position = placement.position
            position.z = floor
            return CollectedActor(
                actor: PlacedActor(
                    copying: collected.actor,
                    placement: PlacedReference.Placement(
                        position: position, rotation: placement.rotation
                    ),
                    scale: collected.actor.scale
                ),
                isPersistent: collected.isPersistent
            )
        }
    }

    /// The top of the highest walkable static surface within reach above `feet`.
    static func floorHeight(under feet: SIMD3<Float>, collision: StaticCollisionSet) -> Float? {
        CapsuleWorldCollider(capsule: .standard).stepSupport(
            at: SIMD2(feet.x, feet.y),
            minimumHeight: feet.z,
            maximumHeight: feet.z + actorFloorReach,
            query: collision.candidates(overlapping:)
        )?.height
    }
}
