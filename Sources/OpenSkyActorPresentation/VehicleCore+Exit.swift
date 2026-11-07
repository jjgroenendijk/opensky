// Where a cart rider stands once its exit idle ends. See docs/engine/vehicles.md.

public import OpenSkyWorldState
import simd

nonisolated extension VehicleCore {
    /// The body bone whose place the exit clip moves from the seat to the ground.
    public static let bodyBone = "NPC COM [COM ]"

    /// The seat pose moved to where `body` stands, a bone in the rider's root frame, so
    /// the rider stays where the exit clip left it instead of at the cart's centre.
    /// `ground` answers the floor height under a point; without one the seat height stays.
    public static func standingPose(
        seat: ReferenceTransformOverride,
        body: VehicleRiderBody,
        ground: (SIMD3<Float>) -> Float?
    ) -> ReferenceTransformOverride {
        let world = matrix(seat) * SIMD4(body.position.x, body.position.y, 0, 1)
        var position = SIMD3(world.x, world.y, seat.position.z)
        let probe = position + SIMD3(0, 0, groundSearchHeight)
        if let floor = ground(probe) {
            position.z = floor
        }
        var rotation = seat.rotation
        if let forward = body.forward, abs(forward.x) + abs(forward.y) > 0.001 {
            // `angleZ` turns clockwise, and the bind pose faces +Y.
            rotation.z += atan2(forward.x, forward.y)
        }
        return ReferenceTransformOverride(position: position, rotation: rotation, scale: seat.scale)
    }
}

/// Where a rider's body bone is and which way it faces, in the rider's root frame.
nonisolated public struct VehicleRiderBody: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let forward: SIMD3<Float>?

    public init(position: SIMD3<Float>, forward: SIMD3<Float>? = nil) {
        self.position = position
        self.forward = forward
    }
}
