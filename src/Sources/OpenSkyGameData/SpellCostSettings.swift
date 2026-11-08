// How a caster's skill lowers a spell's cost. UESP "Skyrim:Magic Overview", Spell Cost:
// "Skill multiplier = 1 − (skill / 400)^0.65". Dual casting: "2.2x spell effectiveness
// for 2.8x spell cost". See docs/engine/spellcasting.md.

import Foundation
import OpenSkyFormatsESM

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
    /// `fMagicDualCastingCostMult`: what a dual cast costs, in single casts.
    public var dualCastCostMult: Float = 2.8
    /// `fMagicDualCastingEffectivenessBase`: what a dual cast does, in single casts.
    public var dualCastEffectiveness: Float = 2.2
    /// `fMagicDualCastingTimeMult`: the charge time of a dual cast, in single charges.
    public var dualCastTimeMult: Float = 1
    /// `fMagicAreaBaseCostMult`: extra cost per foot of area. 0 in `Skyrim.esm`.
    public var areaBaseCostMult: Float = 0
    /// `fMagicAreaScaleMin` and `fMagicAreaScaleMax`: the area the cost term reads.
    public var areaScaleMin: Float = 2.5
    public var areaScaleMax: Float = 100
    /// `fMagicRangeTargetCostMult`: the cost factor of an aimed or target spell. 1 in `Skyrim.esm`.
    public var rangeTargetCostMult: Float = 1

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
        store.read("fMagicDualCastingCostMult", into: &settings, \.dualCastCostMult)
        store.read("fMagicDualCastingEffectivenessBase", into: &settings, \.dualCastEffectiveness)
        store.read("fMagicDualCastingTimeMult", into: &settings, \.dualCastTimeMult)
        store.read("fMagicAreaBaseCostMult", into: &settings, \.areaBaseCostMult)
        store.read("fMagicAreaScaleMin", into: &settings, \.areaScaleMin)
        store.read("fMagicAreaScaleMax", into: &settings, \.areaScaleMax)
        store.read("fMagicRangeTargetCostMult", into: &settings, \.rangeTargetCostMult)
        return settings
    }

    /// The base cost of `spell` with the area and range terms. No source gives their
    /// form, so OpenSky multiplies each effect by `1 + areaBaseCostMult * clamp(area)` and
    /// an aimed or target spell by `rangeTargetCostMult`. Vanilla's 0 and 1 change nothing.
    public func baseCost(of spell: ResolvedSpell) -> Float {
        let stored = Float(spell.cost.cost)
        let ranged: [MagicEffectDelivery] = [.aimed, .targetActor, .targetLocation]
        let isRanged = spell.data.map { ranged.contains($0.delivery) } ?? false
        let range = isRanged && rangeTargetCostMult.isFinite ? max(0, rangeTargetCostMult) : 1
        let usesArea = areaBaseCostMult.isFinite && areaBaseCostMult != 0
        guard !spell.cost.isManual, usesArea || range != 1 else { return stored }
        let costs = spell.effects.map { effect in
            effect.cost * range * areaFactor(area: effect.item.area)
        }
        return SpellCost.total(ofEffectCosts: costs)
    }

    func areaFactor(area: UInt32) -> Float {
        guard area > 0, areaBaseCostMult.isFinite, areaBaseCostMult != 0 else { return 1 }
        let clamped = min(max(Float(area), areaScaleMin), max(areaScaleMin, areaScaleMax))
        return max(0, 1 + areaBaseCostMult * clamped)
    }
}
