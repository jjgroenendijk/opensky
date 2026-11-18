// A swimmer: the same capsule against the same ground as a walker, held up by buoyancy
// instead of pulled down by gravity. See docs/engine/ground-and-water-contact.md#water.

import OpenSkyPhysics
import simd

nonisolated extension WalkController {
    /// A float point this close above the rest depth counts as resting.
    static let swimRestTolerance: Float = 0.01

    struct SwimStep {
        let surface: Float
        /// Vertical speed the swimmer asks for; 0 leaves it to buoyancy.
        let wantedVelocity: Float
        let floatLevel: Float
    }

    /// Buoyancy pushes up with gravity's strength while the float point is deeper than
    /// `SwimRule.floatRestDepth`. A rising swimmer stops at that depth instead of passing it;
    /// above it gravity pulls it back. Rising ground lifts the feet as for a walker.
    mutating func swim(_ water: SwimStep, dt: Float, world: ContactWorld) {
        let floatPoint = SwimRule.floatPointHeight(
            feetHeight: feetPosition.z, bodyHeight: capsule.height, floatLevel: water.floatLevel
        )
        let belowRest = water.surface - floatPoint - SwimRule.floatRestDepth
        if water.wantedVelocity != 0 {
            verticalVelocity = water.wantedVelocity
        } else if belowRest > 0 {
            verticalVelocity = min(verticalVelocity + Self.gravity * dt, belowRest / dt)
        } else if belowRest < -Self.swimRestTolerance {
            verticalVelocity -= Self.gravity * dt
        } else {
            verticalVelocity = 0
        }
        let result = world.collider.move(
            from: feetPosition,
            displacement: SIMD3<Float>(0, 0, verticalVelocity * dt),
            query: world.collisionQuery
        )
        feetPosition = result.position
        hasUnresolvedPenetration = hasUnresolvedPenetration || result.hasUnresolvedPenetration
        var ground = walkableGround(result.contacts)
        if ground != nil, verticalVelocity < 0 {
            verticalVelocity = 0
        }
        if let terrain = touchTerrain(world) {
            ground = terrain
        }
        // The swim rule reads `isGrounded` as "walkable ground below", so search for it.
        land(on: ground ?? probeGround(world))
    }
}
