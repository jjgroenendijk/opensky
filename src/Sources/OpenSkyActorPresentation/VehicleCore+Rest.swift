// A towed cart that stands still keeps its last pose, so it makes no ground search
// until its horse moves it again. See docs/engine/vehicles.md.

import OpenSkyWorldInterface
import simd

nonisolated extension VehicleCore {
    /// Moves a towed follower along the line from where it was toward the hitch, so it
    /// trails the carrier's path: to `length` behind it, or with `dt`, to where the tow
    /// line's spring takes it. It rests on the ground under its wheels, or, before they
    /// are known, on the ground under its origin and the hitch.
    static func pull(
        _ tow: inout VehicleTow, hitch: SIMD4<Float>, ground: (SIMD3<Float>) -> Float?,
        dt: Float = 0
    ) -> float4x4 {
        if let pose = restingPose(of: tow, hitch: hitch, dt: dt) {
            return pose
        }
        let before = tow.motion
        let pose = movedPose(&tow, hitch: hitch, ground: ground, dt: dt)
        let slow = abs(tow.motion.speed) < Self.restSpeed && abs(tow.motion.swing) < Self.restSwing
            && before.hitch.map { simd_distance_squared($0, tow.motion.hitch ?? .zero) < 1e-8 }
            == true
        tow.quietSeconds = dt > 0 && slow ? tow.quietSeconds + dt : 0
        // Slow for half a swing of the tow line, so the turn of a swing is not rest.
        tow.rest = tow.quietSeconds >= Self.restDelay
            ? VehicleTowRest(hitch: tow.motion.hitch ?? .zero, pose: pose) : nil
        return pose
    }

    /// Below these the tow line moves the cart less than 0.02 units a frame, in units and
    /// radians per second. On a slope the line chatters at the end of its play, which
    /// stricter limits never let rest.
    static let restSpeed: Float = 1
    static let restSwing: Float = 0.01
    /// Half the tow line's swing period, so a swing wider than 1/6 unit never rests.
    static let restDelay: Float = 0.5

    /// The pose a cart keeps while it and its hitch stand still: the game's cart is a
    /// set of physics bodies, which make no ground search of their own at rest.
    private static func restingPose(
        of tow: VehicleTow,
        hitch: SIMD4<Float>,
        dt: Float
    ) -> float4x4? {
        guard
            dt > 0, let rest = tow.rest,
            simd_distance_squared(rest.hitch, SIMD3(hitch.x, hitch.y, hitch.z)) < 1e-8
        else { return nil }
        return rest.pose
    }
}
