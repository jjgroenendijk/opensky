// How an NPC archer aims: it leads a moving target, its tracker adds noise to the aim
// point, and the shot leaves inside a spread cone that narrows with Archery skill.
// Read from the game program; see docs/engine/archery.md, NPC aim.

import Foundation
public import OpenSkyConditions
import simd

nonisolated public enum NPCArcheryAim {
    /// The lead is refined at most this many times.
    public static let leadIterations = 10
    /// The lead stops once the flight time changes by less than this, in seconds.
    public static let leadTolerance: Float = 0.05
    /// No lead below this distance or above `maximumLeadDistance`, in game units.
    public static let minimumLeadDistance: Float = 1
    public static let maximumLeadDistance: Float = 8192
    /// The launch direction that lands a shot of `speed` on `point` under `gravity`
    /// (units per second squared, downwards): the low arc. Out of range, 45 degrees up.
    public static func ballistic(
        from origin: SIMD3<Float>, to point: SIMD3<Float>, speed: Float, gravity: Float
    ) -> SIMD3<Float> {
        let offset = point - origin
        let flat = SIMD2(offset.x, offset.y)
        let distance = simd_length(flat)
        guard gravity > 0, gravity.isFinite, speed > 0, distance > Float.ulpOfOne else {
            return normalizedOrX(offset)
        }
        let speed2 = speed * speed
        let root = speed2 * speed2
            - gravity * (gravity * distance * distance + 2 * offset.z * speed2)
        let pitch = root >= 0
            ? atan((speed2 - root.squareRoot()) / (gravity * distance))
            : Float.pi / 4
        let heading = flat / distance
        return SIMD3(heading.x * cos(pitch), heading.y * cos(pitch), sin(pitch))
    }

    /// The tracker's noise: each axis moves by up to variance × base units.
    public static let aimVariance: Float = 0.9
    public static let aimNoiseBase: Float = 16
    /// How far an NPC archer shoots from instead of closing in, in game units. OpenSky's
    /// value (docs/engine/unverified-values.md).
    public static let shootingRange: Float = 2048

    /// Where to aim so a shot of `speed` meets a target at `point` moving at `velocity`.
    public static func lead(
        from origin: SIMD3<Float>, to point: SIMD3<Float>,
        velocity: SIMD3<Float>, speed: Float
    ) -> SIMD3<Float> {
        let distance = simd_distance(origin, point)
        guard
            speed > 0, speed.isFinite, distance >= minimumLeadDistance,
            distance <= maximumLeadDistance, all(velocity .== velocity)
        else { return point }
        var aim = point
        var flight = distance / speed
        for _ in 0 ..< leadIterations {
            aim = point + velocity * flight
            let next = simd_distance(origin, aim) / speed
            defer { flight = next }
            if abs(next - flight) < leadTolerance {
                return point + velocity * next
            }
        }
        return aim
    }

    /// The tracker's noise: a uniform offset of up to ± variance × base on each axis.
    public static func noisy(
        _ point: SIMD3<Float>, random: inout ConditionRandom,
        variance: Float = aimVariance, base: Float = aimNoiseBase
    ) -> SIMD3<Float> {
        let reach = max(0, variance * base)
        guard reach > 0, reach.isFinite else { return point }
        return point + SIMD3(
            (unit(&random) * 2 - 1) * reach,
            (unit(&random) * 2 - 1) * reach,
            (unit(&random) * 2 - 1) * reach
        )
    }

    /// The largest angle a shot leaves the aim line by, in radians.
    public static func maximumSpread(skill: Float, coneDegrees: Float) -> Float {
        guard skill.isFinite, coneDegrees.isFinite else { return 0 }
        let share = min(max((100 - skill) / 100, 0), 1)
        return max(0, coneDegrees) * Float.pi / 180 * share
    }

    /// `direction` turned by a random angle up to `maximum`: the radius is uniform, not
    /// area-uniform, so shots cluster near the centre. The sine part goes to pitch and the
    /// cosine part to heading.
    public static func spread(
        _ direction: SIMD3<Float>, maximum: Float, random: inout ConditionRandom
    ) -> SIMD3<Float> {
        let forward = normalizedOrX(direction)
        guard maximum > 0, maximum.isFinite else { return forward }
        let radius = unit(&random) * maximum
        let angle = unit(&random) * 2 * Float.pi
        let heading = atan2(forward.y, forward.x) - cos(angle) * radius
        let horizontal = simd_length(SIMD2(forward.x, forward.y))
        let pitch = atan2(forward.z, horizontal) + sin(angle) * radius
        return SIMD3(cos(pitch) * cos(heading), cos(pitch) * sin(heading), sin(pitch))
    }

    /// A value in [0, 1) from the seeded generator.
    static func unit(_ random: inout ConditionRandom) -> Float {
        Float(random.next() >> 40) / Float(1 << 24)
    }

    private static func normalizedOrX(_ direction: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(direction)
        guard length.isFinite, length > Float.ulpOfOne else { return SIMD3(1, 0, 0) }
        return direction / length
    }
}

/// One target's feet at the last two combat steps, so an archer can lead it.
nonisolated struct TargetTrack: Equatable, Sendable {
    private(set) var previous: SIMD3<Float>
    private(set) var current: SIMD3<Float>
    private(set) var step: Double
    private(set) var velocity = SIMD3<Float>.zero

    init(feet: SIMD3<Float>, step: Double) {
        previous = feet
        current = feet
        self.step = step
    }

    /// Takes the feet once per step; a later call in the same step changes nothing.
    mutating func note(_ feet: SIMD3<Float>, step now: Double, seconds: Float) {
        guard now != step else { return }
        previous = current
        current = feet
        step = now
        velocity = seconds > 0 ? (current - previous) / seconds : .zero
    }
}
