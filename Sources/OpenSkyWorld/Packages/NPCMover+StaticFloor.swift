// A marker walk keeps to its authored line through rocks and walls, but stands on the
// roads and bridges along it (docs/engine/package-schedules.md).

import OpenSkyPhysics
import OpenSkyRendering
import simd

extension NPCMover {
    /// A walk that ignores statics passes through walls, but still stands on a road or a
    /// bridge in reach of a step, as the game's character controller does.
    func staticFloorSampler(world: NPCMovementWorld) -> WalkController.GroundSampler {
        let reach = controller.feetPosition.z + configuration.stepHeight.value
        let collider = CapsuleWorldCollider(capsule: capsule)
        return { position in
            let terrain = world.sampleGround(position)
            guard
                let floor = collider.stepSupport(
                    at: position,
                    minimumHeight: terrain?.height ?? reach - capsule.height,
                    maximumHeight: reach,
                    query: world.collisionQuery
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
}
