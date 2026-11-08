// Which actor a dragon rider can lock: the cone and range of the view it searches.

import simd

/// An actor seen from the rider's eye: how far off the view centre, and on which side.
nonisolated public struct MountTargetView: Equatable, Sendable {
    /// Radians between the view direction and the actor.
    public let angle: Float
    /// Radians counter-clockwise from the view heading, in -pi...pi.
    public let bearing: Float
}

nonisolated public enum MountTargeting {
    /// How far from the view centre, in radians, an actor can be locked.
    public static let lockCone: Float = 0.25
    /// The farthest a rider locks a target from, in units.
    public static let lockRange: Float = 8000
    /// How far from the view centre, in radians, Switch Target looks: about the view.
    public static let switchCone: Float = .pi / 3
    /// Closer than this, in units, the direction to the actor means nothing.
    public static let nearest: Float = 1

    /// How the actor at `offset` from the eye looks along `forward`, or nil when it is
    /// outside `cone` or the lock range.
    public static func view(
        of offset: SIMD3<Float>, forward: SIMD3<Float>, within cone: Float
    ) -> MountTargetView? {
        let distance = simd_length(offset)
        guard distance > nearest, distance <= lockRange else { return nil }
        let angle = acos(min(max(simd_dot(offset / distance, forward), -1), 1))
        guard angle <= cone else { return nil }
        let heading = atan2(forward.y, forward.x)
        let bearing = remainder(atan2(offset.y, offset.x) - heading, 2 * Float.pi)
        return MountTargetView(angle: angle, bearing: bearing)
    }
}
