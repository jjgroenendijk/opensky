// What a spell actually costs the caster (issue #497, roadmap item 20.4): the
// `Mod Spell Cost` entry point and the SPIT half-cost perk, folded over the
// record's own cost.
//
// A satellite of `CasterRuntime` so that type stays under the strict-lint file
// cap, and along a real seam: everything there is a cast in flight, and this is
// one number the cast asks for at three points — the refusal check, the
// fire-and-forget charge and the concentration drain — which is exactly why it
// is one function rather than three expressions.
//
// ## Two mechanisms for one discount, and why only one of them may fire
//
// The SPIT header names a perk that halves the cost
// (`SpellItemData.halfCostPerk`, decoded since 19.1 and until now consumed by
// nobody), and the `Mod Spell Cost` entry point (38) is a general reduction
// vanilla hooks 43 times — the fourth most-hooked entry point in the game
// (docs/formats/perks.md).
//
// On real records these are usually *the same discount authored twice*.
// `Flames` costs 24 and names `DestructionNovice00` in SPIT, and that perk's
// only effect is `Mod Spell Cost` × 0.5 — measured on this machine's install
// on 2026-08-19. Applying both would charge 6 where the game charges 12, so
// this file applies the header halving only when the perk it names does not
// hook `Mod Spell Cost` itself. Which of the two the original engine reads is
// not documented anywhere OpenSky can cite; what *is* observable is the number
// it charges, and this rule reproduces it under either reading while still
// honouring a mod that authors the header field alone.
//
// Both are gated on ownership, which is the check this item adds: before it,
// the header link was read and the halving applied to everybody.
//
// The spell is the condition tab's `spell` subject, which this engine cannot
// bind to a world reference — a SPEL is not a placed reference — so a spell tab
// is skipped and counted like every other unbound subject
// (`PerkRuntimeEvaluation`).
//
// Documented in docs/engine/perks.md and docs/engine/magic.md.

import Foundation

extension CasterRuntime {
    /// The `Mod Spell Cost` entry point, by its documented id.
    static let spellCostEntryPoint = PerkEntryPoint(rawValue: 38)

    /// What casting `spell` costs `caster` right now, in magicka.
    ///
    /// The record's own cost when no perk runtime is wired, which is what every
    /// synthetic session and every actor with no perks pays.
    func cost(of spell: ResolvedSpell, caster: ActorValueHolder) -> Float {
        let authored = Float(spell.cost.cost)
        guard var perks else { return authored }
        var cost = authored
        if
            let link = spell.data?.halfCostPerk,
            let perk = perks.perks.resolve(link, fromPlugin: spell.sourcePlugin),
            perks.owns(ReferenceKey(resolved: perk.id), on: caster),
            !Self.reducesSpellCost(perk)
        {
            cost /= 2
        }
        let outcome = perks.modify(
            cost,
            at: Self.spellCostEntryPoint,
            on: caster,
            subjects: PerkEvaluationSubjects(owner: caster.key),
            actorValue: { [values] index in values.value(at: index, on: caster) }
        )
        // The tally advanced inside the copy, so hand it back rather than
        // dropping what the evaluation counted.
        self.perks = perks
        return max(0, outcome.value)
    }

    /// Whether `perk` already reduces spell cost through its own entry point,
    /// which is what makes the SPIT halving a duplicate rather than a second
    /// reduction. See the file header for the measured record.
    static func reducesSpellCost(_ perk: ResolvedPerk) -> Bool {
        perk.effects.contains { $0.entryPoint == spellCostEntryPoint }
    }
}
