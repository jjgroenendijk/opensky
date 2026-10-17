// How a caster's skill lowers a spell's cost. UESP "Skyrim:Magic Overview", Spell Cost:
// "Skill multiplier = 1 − (skill / 400)^0.65". See docs/engine/spellcasting.md.

import Foundation

nonisolated public struct SpellCostSettings: Equatable, Sendable {
    /// `fMagicCasterPCSkillCostBase`: 1/400 in the UESP formula.
    public var playerBase: Float = 0.0025
    /// `fMagicPCSkillCostScale`: the exponent 0.65.
    public var playerScale: Float = 0.65
    /// `fMagicCasterSkillCostBase`; Skyrim.esm has no record, so the CK default applies.
    public var actorBase: Float = 0.005
    /// `fMagicCasterSkillCostMult`.
    public var actorMult: Float = 0.5
    /// `fMagicSkillCostScale`.
    public var actorScale: Float = 0.5

    public static let vanilla = Self()

    public init() {}

    /// The share of the base cost a caster pays at `skill`, between 0 and 1.
    public func skillMultiplier(skill: Float, isPlayer: Bool) -> Float {
        let reduction = isPlayer
            ? pow(max(0, skill * playerBase), playerScale)
            : actorMult * pow(max(0, skill * actorBase), actorScale)
        return min(1, max(0, 1 - reduction))
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fMagicCasterPCSkillCostBase", into: &settings, \.playerBase)
        store.read("fMagicPCSkillCostScale", into: &settings, \.playerScale)
        store.read("fMagicCasterSkillCostBase", into: &settings, \.actorBase)
        store.read("fMagicCasterSkillCostMult", into: &settings, \.actorMult)
        store.read("fMagicSkillCostScale", into: &settings, \.actorScale)
        return settings
    }
}
