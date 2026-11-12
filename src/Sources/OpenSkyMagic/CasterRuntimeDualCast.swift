// Dual casting: the same spell begun in both hands at once casts one stronger spell.
// UESP "Skyrim:Magic Overview": "2.2x spell effectiveness for 2.8x spell cost", and
// only once the school's dual casting perk is taken, which `Can Dual Cast Spell`
// decides. See docs/engine/spellcasting.md#dual-casting.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension SpellHand {
    public var other: SpellHand {
        self == .left ? .right : .left
    }
}

extension CasterRuntime {
    /// How long after the first hand the second may begin and still join it.
    /// OpenSky's choice: no record states a window.
    static let dualCastWindowSeconds: Float = 0.25

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

    var costRules: SpellCostRules {
        SpellCostRules(values: values, spellbook: spellbook, settings: costSettings)
    }

    func chargeTime(of spell: ResolvedSpell, dual: Bool) -> Float {
        costRules.chargeTime(of: spell, dual: dual)
    }

    func canDualCast(_ spell: ResolvedSpell, caster: ActorValueHolder) -> Bool {
        costRules.canDualCast(spell, caster: caster, perks: &perks)
    }

    /// The cost of one cast or one second of `spell`, dual or single.
    func castCost(of spell: ResolvedSpell, dual: Bool, caster: ActorValueHolder) -> Float {
        costRules.castCost(of: spell, dual: dual, caster: caster, perks: &perks)
    }

    /// What casting `spell` costs `caster` right now, in magicka.
    func cost(of spell: ResolvedSpell, caster: ActorValueHolder) -> Float {
        costRules.cost(of: spell, caster: caster, perks: &perks)
    }

    public func dualCastEntries(of spell: ResolvedSpell) -> [MagicItemEffect] {
        costRules.dualCastEntries(of: spell)
    }
}
