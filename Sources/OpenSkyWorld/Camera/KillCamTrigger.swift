// When a kill cam plays: a killing blow by the player on the last hostile
// actor nearby, rolled against fKillCamBaseOdds. The arrow test predicts the
// kill before the arrow lands. See docs/engine/kill-cam.md#when-it-plays.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import simd

nonisolated public struct KillCamCandidate: Equatable, Sendable {
    public let key: ReferenceKey
    public let position: SIMD3<Float>
    public let radius: Float
    public let height: Float
    public let health: Float

    public init(
        key: ReferenceKey,
        position: SIMD3<Float>,
        radius: Float,
        height: Float,
        health: Float
    ) {
        self.key = key
        self.position = position
        self.radius = radius
        self.height = height
        self.health = health
    }
}

nonisolated public struct KillCamSettings: Equatable, Sendable {
    public var enabled = true
    /// fKillCamBaseOdds; the install sets 1, so every eligible kill plays.
    public var baseOdds: Float = 1
    /// Vanilla plays a kill cam only on the last enemy; off allows every kill.
    public var lastEnemyOnly = true

    public init() {}
}

nonisolated public enum KillCamTrigger {
    /// Whether a killing blow plays a kill cam.
    public static func shouldPlay(
        settings: KillCamSettings,
        remainingHostiles: Int,
        random: inout ConditionRandom
    ) -> Bool {
        guard settings.enabled else { return false }
        if settings.lastEnemyOnly, remainingHostiles > 0 {
            return false
        }
        let odds = min(max(settings.baseOdds, 0), 1)
        return odds >= 1 || Float(random.percent()) < odds * 100
    }

    /// The nearest actor the arrow ray meets whose health the damage covers.
    public static func arrowKill(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        range: Float,
        damage: Float,
        candidates: [KillCamCandidate]
    ) -> KillCamCandidate? {
        let length = simd_length(direction)
        guard length > 0, range > 0 else { return nil }
        let unit = direction / length
        return candidates
            .compactMap { candidate -> (KillCamCandidate, Float)? in
                guard candidate.health > 0, candidate.health <= damage else { return nil }
                return rayCapsule(origin, unit, range, candidate).map { (candidate, $0) }
            }
            .min { $0.1 < $1.1 }?.0
    }

    /// Distance along the ray to its closest approach with an upright
    /// capsule, or nil when that approach is wider than the radius.
    static func rayCapsule(
        _ origin: SIMD3<Float>,
        _ unit: SIMD3<Float>,
        _ range: Float,
        _ capsule: KillCamCandidate
    ) -> Float? {
        let low = capsule.position.z + capsule.radius
        let high = capsule.position.z + max(capsule.radius, capsule.height - capsule.radius)
        let axis = SIMD2(capsule.position.x, capsule.position.y)
        // Closest approach in the ground plane, then clamp along the ray.
        let flat = SIMD2(unit.x, unit.y)
        let flatLength = simd_length_squared(flat)
        let toAxis = axis - SIMD2(origin.x, origin.y)
        var along = flatLength > 0 ? simd_dot(toAxis, flat) / flatLength : 0
        along = min(max(along, 0), range)
        let point = origin + unit * along
        let nearest = SIMD3(axis.x, axis.y, min(max(point.z, low), high))
        return simd_distance(point, nearest) <= capsule.radius ? along : nil
    }
}
