// A spell's real cost: the caster's school skill, then `Mod Spell Cost` and the SPIT
// half-cost perk, both only if owned.
// Vanilla often authors one discount twice (`Flames` 24 with `DestructionNovice00`
// charges 12), so the SPIT halving applies only when that perk has no `Mod Spell Cost`.
// The spell condition tab runs on the spell, through its effects' keywords.
// See docs/engine/perks.md and docs/engine/spellcasting.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

/// What a spell costs a caster and how long it charges, single or dual, after the
/// caster's skill and perks.
struct SpellCostRules {
    let values: any ActorValueAccess
    let spellbook: SpellbookRuntime
    let settings: SpellCostSettings

    /// The `Mod Spell Cost` entry point, by its documented id.
    static let spellCostEntryPoint = PerkEntryPoint.modSpellCost

    /// What casting `spell` costs `caster` right now, in magicka.
    ///
    /// Without a perk runtime, the skill-lowered cost is all a caster pays.
    func cost(
        of spell: ResolvedSpell, caster: ActorValueHolder, perks: inout (any PerkAccess)?
    ) -> Float {
        let skill = spell.magicSkill.flatMap { values.value(at: $0, on: caster) } ?? 0
        let authored = settings.baseCost(of: spell)
            * settings.skillMultiplier(skill: skill, isPlayer: caster.key == .player)
        guard var access = perks, !spell.isStaff else { return authored }
        var cost = authored
        if
            let link = spell.data?.halfCostPerk,
            let perk = access.perks.resolve(link, fromPlugin: spell.sourcePlugin),
            access.owns(ReferenceKey(resolved: perk.id), on: caster),
            !Self.reducesSpellCost(perk)
        {
            cost /= 2
        }
        access
            .conditions[resolution: SpellEvaluationResolution.self] =
            SpellEvaluationResolution(spell: spell)
        let outcome = access.modify(
            cost,
            at: Self.spellCostEntryPoint,
            on: caster,
            subjects: PerkEvaluationSubjects(owner: caster.key)
                .binding(.spell, to: spellbook.spells.conditionSubject(of: spell)),
            actorValue: { [values] index in values.value(at: index, on: caster) }
        )
        access.conditions.clear(SpellEvaluationResolution.self)
        // The tally advanced inside the copy, so hand it back rather than
        // dropping what the evaluation counted.
        perks = access
        return max(0, outcome.value)
    }

    /// Whether `perk` already reduces spell cost through its own entry point,
    /// which is what makes the SPIT halving a duplicate rather than a second
    /// reduction. See the file header for the measured record.
    static func reducesSpellCost(_ perk: ResolvedPerk) -> Bool {
        perk.effects.contains { $0.entryPoint == spellCostEntryPoint }
    }

    /// The `SPIT` charge time, scaled by `fMagicDualCastingTimeMult` for a dual cast.
    func chargeTime(of spell: ResolvedSpell, dual: Bool) -> Float {
        let single = max(0, spell.data?.chargeTime ?? 0)
        return dual ? single * max(0, settings.dualCastTimeMult) : single
    }

    static let canDualCastEntryPoint = PerkEntryPoint.canDualCastSpell
    /// Whether `caster` may dual cast `spell`: a spell rather than a power, and a
    /// perk whose `Can Dual Cast Spell` entry passes for it.
    func canDualCast(
        _ spell: ResolvedSpell, caster: ActorValueHolder, perks: inout (any PerkAccess)?
    ) -> Bool {
        guard
            spell.spellType == .spell, spell.data?.castingType != .constantEffect,
            var access = perks
        else { return false }
        access
            .conditions[resolution: SpellEvaluationResolution.self] =
            SpellEvaluationResolution(spell: spell)
        let outcome = access.modify(
            0,
            at: Self.canDualCastEntryPoint,
            on: caster,
            subjects: PerkEvaluationSubjects(owner: caster.key)
                .binding(.spell, to: spellbook.spells.conditionSubject(of: spell)),
            actorValue: { [values] index in values.value(at: index, on: caster) }
        )
        access.conditions.clear(SpellEvaluationResolution.self)
        perks = access
        return outcome.value > 0
    }

    /// The cost of one cast or one second of `spell`, dual or single.
    func castCost(
        of spell: ResolvedSpell, dual: Bool, caster: ActorValueHolder,
        perks: inout (any PerkAccess)?
    ) -> Float {
        let single = cost(of: spell, caster: caster, perks: &perks)
        return dual ? single * max(0, settings.dualCastCostMult) : single
    }

    /// The entries a dual cast applies. An entry grows only where its MGEF lets
    /// power change magnitude or duration, and not at all for a spell flagged
    /// "No Dual Cast Modifications".
    func dualCastEntries(of spell: ResolvedSpell) -> [MagicItemEffect] {
        guard spell.data?.flags.contains(.noDualCastModifications) != true else {
            return spell.record.effects
        }
        let power = settings.dualCastEffectiveness
        return spell.effects.map { resolved in
            let flags = resolved.effect?.effect.data?.flags ?? []
            let entry = resolved.item
            return entry.with(
                magnitude: entry.magnitude
                    * (flags.contains(.powerAffectsMagnitude) ? power : 1),
                duration: Float(entry.duration)
                    * (flags.contains(.powerAffectsDuration) ? power : 1)
            )
        }
    }
}
