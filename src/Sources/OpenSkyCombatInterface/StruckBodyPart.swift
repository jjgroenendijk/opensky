// The body part a hit struck, and what its `BPND` values do to the hit.
// See docs/formats/body-parts.md#in-the-game.

public import OpenSkyFormatsESM
import simd

/// The part of the target's `BPTD` that a hit struck.
nonisolated public struct StruckBodyPart: Equatable, Sendable {
    /// `BPND` part type: 0 torso, 1 head, 2 eye, 3 look-at, 4 fly grab, 5 saddle.
    public var partType: UInt8
    public var node: String
    /// The node's place in the world when the hit landed.
    public var position: SIMD3<Float>
    public var damageMultiplier: Float
    public var healthPercent: UInt8
    /// An AVIF index, or nil for none.
    public var actorValue: Int32?
    /// Set when the part has the explodable flag, so a killing blow rolls on it.
    public var explodable: ExplodablePart?
    /// The severable `IPDS`, in the load-order FormID space, that sprays blood around.
    public var bloodImpactDataSet: FormID?

    public init(
        partType: UInt8,
        node: String,
        position: SIMD3<Float> = .zero,
        damageMultiplier: Float = 1,
        healthPercent: UInt8 = 0,
        actorValue: Int32? = nil,
        explodable: ExplodablePart? = nil,
        bloodImpactDataSet: FormID? = nil
    ) {
        self.partType = partType
        self.node = node
        self.position = position
        self.damageMultiplier = damageMultiplier
        self.healthPercent = healthPercent
        self.actorValue = actorValue
        self.explodable = explodable
        self.bloodImpactDataSet = bloodImpactDataSet
    }
}

/// Where a part sits in the world, for the pick.
nonisolated public struct BodyPartPlacement: Equatable, Sendable {
    public var partType: UInt8
    public var position: SIMD3<Float>
    /// The `BPND` to-hit chance. A part at 0 is never noted.
    public var toHitChance: UInt8

    public init(partType: UInt8, position: SIMD3<Float>, toHitChance: UInt8) {
        self.partType = partType
        self.position = position
        self.toHitChance = toHitChance
    }
}

nonisolated public enum BodyPartHitRules {
    /// The pick of the part a hit at `point` struck: the part whose node lies nearest.
    /// A part with a to-hit chance of 0 gives none.
    public static func struckPart(
        _ parts: [BodyPartPlacement], at point: SIMD3<Float>
    ) -> BodyPartPlacement? {
        guard
            let nearest = parts.min(by: {
                simd_distance_squared($0.position, point)
                    < simd_distance_squared($1.position, point)
            }),
            nearest.toHitChance > 0
        else { return nil }
        return nearest
    }

    /// The part's multiplier counts only for a ranged weapon, and never lowers a hit.
    public static func damageMultiplier(of part: StruckBodyPart?, kind: CombatHitKind) -> Float {
        guard let part, kind == .ranged, part.damageMultiplier.isFinite else { return 1 }
        return max(1, part.damageMultiplier)
    }

    /// `damage / (base Health * health percent / 100) * 100`, then the player's limb
    /// multiplier. A health percent of 0 gives none; a base Health of 0 or less gives
    /// the raw damage.
    public static func limbDamage(
        _ damage: Float, part: StruckBodyPart, baseHealth: Float, playerMultiplier: Float?
    ) -> Float {
        guard part.healthPercent > 0, damage > 0 else { return 0 }
        let share = baseHealth > 0
            ? damage / (baseHealth * Float(part.healthPercent) / 100) * 100 : damage
        return share * (playerMultiplier ?? 1)
    }

    /// Blood around a hit sprays along twice the hit direction plus a jitter of up to
    /// 0.3 on each axis, and its ray runs 0.5 lower.
    public static let bloodSprayChance: Float = 0.75
    public static let bloodSprayJitter: Float = 0.3
    public static let bloodSprayDrop: Float = 0.5
    public static let bloodSprayReach: Float = 512

    /// The direction of the blood ray. `jitter` holds three draws from -1 to 1.
    public static func bloodRay(
        hitDirection: SIMD3<Float>, jitter: SIMD3<Float>
    ) -> SIMD3<Float>? {
        guard simd_length_squared(hitDirection) > 1e-8 else { return nil }
        let spray = simd_normalize(simd_normalize(hitDirection) * 2 + jitter * bloodSprayJitter)
        var ray = spray
        ray.z -= bloodSprayDrop
        return simd_length_squared(ray) > 1e-8 ? simd_normalize(ray) : nil
    }
}
