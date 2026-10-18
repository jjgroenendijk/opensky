// While `SetPlayerAIDriven` holds, a package walks the player like an NPC, along a
// navmesh path. The walk turns the view to the next waypoint and holds forward, so the
// player's own capsule, collision, and walk speed move the player.
// See docs/engine/package-schedules.md.

import simd

nonisolated public enum PlayerPackageWalk {
    /// Near enough on the ground. The player walks about 5 units a frame, so this
    /// is wider than an NPC mover's waypoint.
    public static let arrivalRadius: Float = 40

    /// The view yaw that faces `target` from `feet`, or nil once the player has arrived.
    public static func steeringYaw(feet: SIMD3<Float>, target: SIMD3<Float>) -> Float? {
        let delta = SIMD2(target.x - feet.x, target.y - feet.y)
        guard simd_length(delta) > arrivalRadius else { return nil }
        return atan2f(delta.y, delta.x)
    }

    /// The path without the waypoints the player has already reached.
    public static func remainingPath(_ path: [SIMD3<Float>], feet: SIMD3<Float>) -> [SIMD3<Float>] {
        Array(path.drop { steeringYaw(feet: feet, target: $0) == nil })
    }
}
