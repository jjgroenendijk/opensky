// Dual casting: the same spell begun in both hands at once casts one stronger spell.
// UESP "Skyrim:Magic Overview": "2.2x spell effectiveness for 2.8x spell cost", and
// only once the school's dual casting perk is taken, which `Can Dual Cast Spell`
// decides. See docs/engine/spellcasting.md#dual-casting.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension SpellHand {
    public var other: SpellHand {
        self == .left ? .right : .left
    }
}

extension CasterRuntime {
    /// The `SPIT` charge time, scaled by `fMagicDualCastingTimeMult` for a dual cast.
    func chargeTime(of spell: ResolvedSpell, dual: Bool) -> Float {
        let single = max(0, spell.data?.chargeTime ?? 0)
        return dual ? single * max(0, costSettings.dualCastTimeMult) : single
    }

    public static let canDualCastEntryPoint = PerkEntryPoint.canDualCastSpell
    /// How long after the first hand the second may begin and still join it.
    /// OpenSky's choice: no record states a window.
    public static let dualCastWindowSeconds: Float = 0.25

    /// Whether `caster` may dual cast `spell`: a spell rather than a power, and a
    /// perk whose `Can Dual Cast Spell` entry passes for it.
    public func canDualCast(_ spell: ResolvedSpell, caster: ActorValueHolder) -> Bool {
        guard
            spell.spellType == .spell, spell.data?.castingType != .constantEffect,
            var perks
        else { return false }
        perks.conditions.spellEvaluation = SpellEvaluationResolution(spell: spell)
        let outcome = perks.modify(
            0,
            at: Self.canDualCastEntryPoint,
            on: caster,
            subjects: PerkEvaluationSubjects(owner: caster.key)
                .binding(.spell, to: spellbook.spells.conditionSubject(of: spell)),
            actorValue: { [values] index in values.value(at: index, on: caster) }
        )
        perks.conditions.clear(SpellEvaluationResolution.self)
        self.perks = perks
        return outcome.value > 0
    }

    /// Joins `hand` to a young cast of the same spell in the other hand. Returns
    /// false when the two stay single casts.
    func joinDualCast(
        _ hand: SpellHand, spell: ResolvedSpell, caster: ActorValueHolder
    ) -> Bool {
        var lead = state(of: hand.other, on: caster.key)
        guard
            lead.spell == spell.key, !lead.isDualCast, lead.phase.isCasting,
            lead.age <= Self.dualCastWindowSeconds + SpellCastState.secondTolerance,
            canDualCast(spell, caster: caster),
            castCost(of: spell, dual: true, caster: caster) <= values.current(of: caster).magicka
        else { return false }
        lead.joinDualCast(as: .lead)
        casts[slot(hand.other, caster)] = lead
        var partner = SpellCastState()
        partner.beginCharge(spell.key)
        partner.joinDualCast(as: .partner)
        casts[slot(hand, caster)] = partner
        tally.noteDualCast()
        return true
    }

    /// The hand that runs `hand`'s cast: the other hand for a dual partner.
    func leadHand(of hand: SpellHand, on caster: ReferenceKey) -> SpellHand {
        state(of: hand, on: caster).dualRole == .partner ? hand.other : hand
    }

    /// Ends the partner of a dual cast whose lead in `hand` just ended.
    func endDualPartner(of hand: SpellHand, lead: SpellCastState, caster: ActorValueHolder) {
        guard lead.dualRole == .lead else { return }
        casts[slot(hand.other, caster)] = SpellCastState()
    }

    /// The cost of one cast or one second of `spell`, dual or single.
    public func castCost(of spell: ResolvedSpell, dual: Bool, caster: ActorValueHolder) -> Float {
        let single = cost(of: spell, caster: caster)
        return dual ? single * max(0, costSettings.dualCastCostMult) : single
    }

    /// The entries a dual cast applies. An entry grows only where its MGEF lets
    /// power change magnitude or duration, and not at all for a spell flagged
    /// "No Dual Cast Modifications".
    public func dualCastEntries(of spell: ResolvedSpell) -> [MagicItemEffect] {
        guard spell.data?.flags.contains(.noDualCastModifications) != true else {
            return spell.record.effects
        }
        let power = costSettings.dualCastEffectiveness
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
