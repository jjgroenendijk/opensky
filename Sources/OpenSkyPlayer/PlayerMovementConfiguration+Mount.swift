// The gaits of a ridden horse, read from the horse's movement types (docs/engine/riding.md).

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

nonisolated extension PlayerMovementConfiguration {
    /// The horse's own movement types: walk and run from `Horse_Default_MT`, sprint
    /// from `Horse_Sprint_MT`. Jump and step height are the player's.
    public static func mount(
        movementTypes: MovementTypeStore, rider: PlayerMovementConfiguration
    ) -> PlayerMovementConfiguration {
        let walk = gait(
            editorID: MountMovementTypes.walking, slot: .walk, store: movementTypes,
            fallback: 125, fallbackSource: "OpenSky fallback (no Horse_Default_MT)"
        )
        let run = gait(
            editorID: MountMovementTypes.walking, slot: .run, store: movementTypes,
            fallback: 450, fallbackSource: "OpenSky fallback (no Horse_Default_MT)"
        )
        return PlayerMovementConfiguration(
            walkSpeed: walk,
            runSpeed: run,
            stepHeight: rider.stepHeight,
            sprintSpeed: gait(
                editorID: MountMovementTypes.sprinting, slot: .run, store: movementTypes,
                fallback: 600, fallbackSource: "OpenSky fallback (no Horse_Sprint_MT)"
            ),
            sneakSpeed: walk,
            swimSpeed: walk,
            jumpTakeoffSpeed: rider.jumpTakeoffSpeed,
            travelSpeed: walk
        )
    }
}

/// The movement types a ridden horse reads.
nonisolated public enum MountMovementTypes: Sendable {
    public static let walking = "Horse_Default_MT"
    public static let sprinting = "Horse_Sprint_MT"
    /// The capsule a ridden horse collides with. OpenSky's value; the horse's own
    /// collision is a Havok shape OpenSky does not read.
    public static let capsule = PlayerCapsule(radius: 40, height: 160, eyeHeight: 150)
}
