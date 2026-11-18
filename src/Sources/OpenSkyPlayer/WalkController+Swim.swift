// A swimmer: the same capsule against the same ground as a walker, held up by buoyancy
// instead of pulled down by gravity. See docs/engine/ground-and-water-contact.md#water.

import OpenSkyPhysics
import simd

nonisolated extension WalkController {
    /// How fast a swimmer's vertical speed fades once its float point is near the surface,
    /// per second, so it settles instead of bobbing.
    static let swimSettleDamping: Float = 4

    struct SwimStep {
        let surface: Float
        /// Vertical speed the swimmer asks for; 0 leaves it to buoyancy.
        let wantedVelocity: Float
        let floatLevel: Float
    }

    /// Buoyancy pushes up with gravity's strength while the float point is deeper than
    /// `SwimRule.floatRestDepth`. Above that no push is added, and above the surface
    /// gravity pulls it back. Rising ground lifts the feet as for a walker.
    mutating func swim(_ water: SwimStep, dt: Float, world: ContactWorld) {
        let floatPoint = SwimRule.floatPointHeight(
            feetHeight: feetPosition.z, bodyHeight: capsule.height, floatLevel: water.floatLevel
        )
        let floatDepth = water.surface - floatPoint
        if water.wantedVelocity != 0 {
            verticalVelocity = water.wantedVelocity
        } else if floatDepth > SwimRule.floatRestDepth {
            verticalVelocity += Self.gravity * dt
        } else {
            if floatDepth < 0 {
                verticalVelocity -= Self.gravity * dt
            }
            verticalVelocity *= max(0, 1 - Self.swimSettleDamping * dt)
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
