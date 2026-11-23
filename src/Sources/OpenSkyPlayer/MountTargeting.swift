// Which actors a dragon rider can lock or switch to: the range of the lock and the
// cone of the view Switch Target searches.
// docs/engine/combat-assist.md#flying-mount-lock.

import simd

/// An actor seen from the rider's eye: how far off the view centre, and on which side.
nonisolated public struct MountTargetView: Equatable, Sendable {
    /// Radians between the view direction and the actor.
    public let angle: Float
    /// Radians counter-clockwise from the view heading, in -pi...pi.
    public let bearing: Float
}

nonisolated public enum MountTargeting {
    /// `fTargetLockXYRange`: candidates are gathered this far away, on the ground plane.
    public static let lockRange: Float = 7500
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
        let ground = simd_length(SIMD2(offset.x, offset.y))
        guard distance > nearest, ground <= lockRange else { return nil }
        let angle = acos(min(max(simd_dot(offset / distance, forward), -1), 1))
        guard angle <= cone else { return nil }
        let heading = atan2(forward.y, forward.x)
        let bearing = remainder(atan2(offset.y, offset.x) - heading, 2 * Float.pi)
        return MountTargetView(angle: angle, bearing: bearing)
    }

    /// The actors the lock can take, nearest to `centre` first: those within the lock
    /// range of it on the ground plane. The order is OpenSky's.
    public static func lockOrder<Key>(
        of actors: [(key: Key, feet: SIMD3<Float>)], around centre: SIMD3<Float>
    ) -> [Key] {
        actors
            .map { actor in
                let offset = SIMD2(actor.feet.x - centre.x, actor.feet.y - centre.y)
                return (key: actor.key, distance: simd_length(offset))
            }
            .filter { $0.distance <= lockRange }
            .sorted { $0.distance < $1.distance }
            .map(\.key)
    }
}
