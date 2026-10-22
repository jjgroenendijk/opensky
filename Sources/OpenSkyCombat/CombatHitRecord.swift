// One landed health hit, as the death effects read it: how hard it was, what kind of
// attack it was, and who struck. The killing hit pushes the body, and a qualifying
// blow can sever the head (docs/engine/ragdoll.md#death-effects).

import OpenSkyFormatsESM
import simd

nonisolated public enum CombatHitKind: String, Equatable, Sendable {
    case melee
    case ranged
    case spell
    /// A fall, a trap, an explosion, or another hit with no attack behind it.
    case other
}

nonisolated public struct CombatHitRecord: Equatable, Sendable {
    /// Health the hit took, after difficulty.
    public var damage: Float
    public var kind: CombatHitKind
    public var attacker: ReferenceKey?
    /// Where the hit came from, when no attacker stands there, such as a spell's impact.
    public var origin: SIMD3<Float>?
    /// A standing power attack with an edged or heavy weapon, by an attacker with the
    /// decapitation perk of its weapon's skill.
    public var canSever: Bool

    public init(
        damage: Float,
        kind: CombatHitKind,
        attacker: ReferenceKey? = nil,
        origin: SIMD3<Float>? = nil,
        canSever: Bool = false
    ) {
        self.damage = damage
        self.kind = kind
        self.attacker = attacker
        self.origin = origin
        self.canSever = canSever
    }
}
