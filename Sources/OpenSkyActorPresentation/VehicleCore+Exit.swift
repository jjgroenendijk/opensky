// Where a cart rider stands once its exit idle ends. See docs/engine/vehicles.md.

import OpenSkyWorldState
import simd

nonisolated extension VehicleCore {
    /// The body bone whose place the exit clip moves from the seat to the ground.
    public static let bodyBone = "NPC COM [COM ]"

    /// The seat pose moved to where `body` stands, a bone in the rider's root frame, so
    /// the rider stays where the exit clip left it instead of at the cart's centre.
    /// `ground` answers the floor height under a point; without one the seat height stays.
    public static func standingPose(
        seat: ReferenceTransformOverride,
        body: SIMD3<Float>,
        ground: (SIMD3<Float>) -> Float?
    ) -> ReferenceTransformOverride {
        let world = matrix(seat) * SIMD4(body.x, body.y, 0, 1)
        var position = SIMD3(world.x, world.y, seat.position.z)
        let probe = position + SIMD3(0, 0, groundSearchHeight)
        if let floor = ground(probe) {
            position.z = floor
        }
        return ReferenceTransformOverride(
            position: position, rotation: seat.rotation, scale: seat.scale
        )
    }
}
