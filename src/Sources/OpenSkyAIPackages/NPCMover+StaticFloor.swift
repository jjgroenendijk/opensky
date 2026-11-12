// A marker walk keeps to its authored line through rocks and walls, but stands on the
// roads and bridges along it (docs/engine/package-schedules.md).

import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyWorldInterface
import simd

extension NPCMover {
    func staticFloorSampler(world: NPCMovementWorld) -> WalkController.GroundSampler {
        let legEnd = path.waypoints.indices.contains(waypointIndex)
            ? path.waypoints[waypointIndex] : legStart
        return NPCStaticFloor(
            capsule: capsule, feetHeight: controller.feetPosition.z,
            step: configuration.stepHeight.value, leg: (legStart, legEnd)
        ).sampler(world: world, query: world.collisionQuery(for: actor))
    }
}

/// The floor of a walk that ignores statics, along one leg of its path.
struct NPCStaticFloor {
    let capsule: PlayerCapsule
    let feetHeight: Float
    let step: Float
    let leg: (start: SIMD3<Float>, end: SIMD3<Float>)

    /// A walk that ignores statics passes through walls, but still stands on a road or a
    /// bridge in reach of a step. The floor must also lie within a step of the leg's
    /// line, so a walk through a rock arch does not climb its ledges onto the roof.
    func sampler(
        world: NPCMovementWorld, query: @escaping WalkController.CollisionQuery
    ) -> WalkController.GroundSampler {
        let reach = feetHeight + step
        let collider = CapsuleWorldCollider(capsule: capsule)
        let (start, legEnd) = leg
        let step = step
        let capsule = capsule
        return { position in
            let terrain = world.sampleGround(position)
            let line = Self.lineHeight(at: position, from: start, to: legEnd) + step
            guard
                let floor = collider.stepSupport(
                    at: position,
                    minimumHeight: terrain?.height ?? reach - capsule.height,
                    maximumHeight: min(reach, line),
                    query: query
                ),
                floor.height > terrain?.height ?? -.greatestFiniteMagnitude
            else { return terrain }
            return TerrainGroundSample(
                height: floor.height,
                normal: SIMD3(0, 0, 1),
                material: floor.material
            )
        }
    }

    /// The leg's height above `position`, from its closest point on the leg.
    static func lineHeight(
        at position: SIMD2<Float>, from start: SIMD3<Float>, to end: SIMD3<Float>
    ) -> Float {
        let flat = SIMD2(end.x - start.x, end.y - start.y)
        let lengthSquared = simd_length_squared(flat)
        guard lengthSquared > 0 else { return max(start.z, end.z) }
        let along = simd_dot(position - SIMD2(start.x, start.y), flat) / lengthSquared
        return start.z + (end.z - start.z) * min(max(along, 0), 1)
    }
}
