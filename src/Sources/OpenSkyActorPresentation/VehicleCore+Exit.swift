// Where a cart rider stands once its exit idle ends. See docs/engine/vehicles.md.

public import OpenSkyWorldState
import simd

nonisolated extension VehicleCore {
    /// The body bone whose place the exit clip moves from the seat to the ground.
    static let bodyBone = "NPC COM [COM ]"

    /// The seat pose moved to where `body` stands, a bone in the rider's root frame, so
    /// the rider stays where the exit clip left it instead of at the cart's centre.
    /// `ground` answers the floor height under a point; without one the seat height stays.
    /// `start` moved by an exit clip's travel in its own frame (+x right, +y forward) and
    /// turned by its counter-clockwise yaw, upright on the ground under it.
    public static func travelled(
        _ start: ReferenceTransformOverride,
        by travel: VehicleRiderTravel,
        ground: (SIMD3<Float>) -> Float?
    ) -> ReferenceTransformOverride {
        let heading = start.rotation.z
        let forward = SIMD2(sin(heading), cos(heading))
        let right = SIMD2(forward.y, -forward.x)
        let step = right * travel.offset.x + forward * travel.offset.y
        var position = start.position + SIMD3(step.x, step.y, travel.offset.z)
        if let floor = ground(position + SIMD3(0, 0, groundSearchHeight)) {
            position.z = floor
        }
        return ReferenceTransformOverride(
            position: position, rotation: SIMD3(0, 0, heading - travel.yaw), scale: start.scale
        )
    }

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

/// How far an idle's motion table has carried the rider's root: an offset in the frame
/// the idle started in, and a counter-clockwise turn in radians.
nonisolated public struct VehicleRiderTravel: Equatable, Sendable {
    public let offset: SIMD3<Float>
    public let yaw: Float

    public init(offset: SIMD3<Float>, yaw: Float) {
        self.offset = offset
        self.yaw = yaw
    }
}

/// Where a rider's body bone is and which way it faces, in the rider's root frame.
nonisolated public struct VehicleRiderBody: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let forward: SIMD3<Float>?

    init(position: SIMD3<Float>, forward: SIMD3<Float>? = nil) {
        self.position = position
        self.forward = forward
    }
}
