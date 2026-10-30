// How much a fall hurts, from the `fJumpFall*` settings. The formula and the vanilla
// values are UESP "Skyrim:Damage", Fall Damage (docs/engine/combat.md#fall-damage).

import Foundation
import OpenSkyGameData

nonisolated public struct FallDamageSettings: Equatable, Sendable {
    /// One actor kind's curve: no damage up to `heightMin`, then
    /// `((height - heightMin) * mult) ^ exponent`.
    nonisolated public struct Curve: Equatable, Sendable {
        public var heightMin: Float
        public var mult: Float
        public var exponent: Float

        public init(heightMin: Float, mult: Float, exponent: Float) {
            self.heightMin = heightMin
            self.mult = mult
            self.exponent = exponent
        }

        public func damage(height: Float) -> Float {
            let excess = (height - heightMin) * mult
            guard excess > 0, excess.isFinite, exponent.isFinite else { return 0 }
            let damage = powf(excess, exponent)
            return damage.isFinite ? damage : 0
        }
    }

    /// `fJumpFallHeightMin`, `fJumpFallHeightMult`, `fJumpFallHeightExponent`.
    public var player = Curve(heightMin: 600, mult: 0.1, exponent: 1.45)
    /// The same three settings with the `NPC` suffix.
    public var npc = Curve(heightMin: 450, mult: 0.1, exponent: 1.65)
    /// `fJumpFallVelocityMin`: a slower landing does no damage, units per second.
    public var velocityMin: Float = 700

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        let fields: [(String, WritableKeyPath<Self, Float>)] = [
            ("fJumpFallHeightMin", \.player.heightMin),
            ("fJumpFallHeightMult", \.player.mult),
            ("fJumpFallHeightExponent", \.player.exponent),
            ("fJumpFallHeightMinNPC", \.npc.heightMin),
            ("fJumpFallHeightMultNPC", \.npc.mult),
            ("fJumpFallHeightExponentNPC", \.npc.exponent),
            ("fJumpFallVelocityMin", \.velocityMin)
        ]
        for (editorID, keyPath) in fields {
            store.read(editorID, into: &settings, keyPath)
        }
        return settings
    }

    /// The damage before perks and difficulty. A landing slower than `velocityMin`
    /// does none.
    public func damage(height: Float, speed: Float, isPlayer: Bool) -> Float {
        guard speed >= velocityMin else { return 0 }
        return (isPlayer ? player : npc).damage(height: height)
    }
}
