// A standing actor that a trap or `PushActorAway` knocked back. It slides on its own
// capsule, with the player's knockback rule, until the push fades
// (docs/engine/traps.md#impulses-and-pushback).

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyWorldState
import simd

public struct NPCKnockbackSlide {
    /// Below this horizontal speed, units per second, a grounded slide is over.
    public static let settleSpeed: Float = 5
    /// The longest a slide runs, seconds, so an actor stuck in the air still settles.
    public static let maximumDuration: Float = 3

    public let actor: ReferenceKey
    public let formID: FormID
    public let scale: Float
    /// Where the current cell build draws the actor, which the draw delta starts from.
    public internal(set) var authoredPlacement: PlacedReference.Placement
    public let yaw: Float
    public private(set) var controller: WalkController
    private var elapsed: Float = 0

    public init(
        start: NPCFaceStart,
        feetPosition: SIMD3<Float>,
        yaw: Float,
        configuration: PlayerMovementConfiguration,
        drawnPlacement: PlacedReference.Placement? = nil
    ) {
        actor = start.actor
        formID = start.formID
        scale = start.scale
        authoredPlacement = drawnPlacement ?? start.placement
        self.yaw = yaw
        let capsule = PlayerCapsule.standard
        controller = WalkController(
            cameraPosition: feetPosition + SIMD3(0, 0, capsule.eyeHeight),
            capsule: capsule,
            configuration: configuration
        )
    }

    public mutating func knock(_ velocity: SIMD3<Float>) {
        controller.knock(velocity)
        elapsed = 0
    }

    /// Slides one frame. Returns true once the push has faded on the ground.
    public mutating func advance(by frameTime: Float, world: NPCMovementWorld) -> Bool {
        controller.update(
            frameTime: frameTime,
            yaw: yaw,
            sampleGround: world.sampleGround,
            collisionQuery: world.collisionQuery(for: actor)
        ) { _ in LocomotionStepPlan() }
        elapsed += max(frameTime, 0)
        let faded = controller.isGrounded
            && simd_length(controller.knockback) < Self.settleSpeed
        return faded || elapsed >= Self.maximumDuration
    }

    public var transform: ReferenceTransformOverride {
        ReferenceTransformOverride(
            position: controller.feetPosition,
            rotation: SIMD3(
                authoredPlacement.rotation.x, authoredPlacement.rotation.y,
                NPCYawMath.heading(fromYaw: yaw)
            ),
            scale: scale
        )
    }

    public var instanceDelta: float4x4 {
        NPCDrawDelta.from(drawn: authoredPlacement, to: transform, scale: scale)
    }

    public var readout: NPCMovementReadout {
        readout(as: .knockedBack)
    }

    /// The same readout with another state, for the rest a faded slide leaves.
    public func readout(as state: NPCMovementState) -> NPCMovementReadout {
        NPCMovementReadout(
            actor: actor, state: state, feetPosition: controller.feetPosition, yaw: yaw,
            waypointIndex: 0, waypointCount: 0, gait: .walk, repathCount: 0
        )
    }

    public func persistence(reason: NPCMovementSettleReason) -> NPCMovementPersistence {
        NPCMovementPersistence(actor: actor, transform: transform, cell: nil, reason: reason)
    }
}
