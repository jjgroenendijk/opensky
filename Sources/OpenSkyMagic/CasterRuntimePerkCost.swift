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

extension CasterRuntime {
    /// The `Mod Spell Cost` entry point, by its documented id.
    public static let spellCostEntryPoint = PerkEntryPoint.modSpellCost

    /// What casting `spell` costs `caster` right now, in magicka.
    ///
    /// Without a perk runtime, the skill-lowered cost is all a caster pays.
    public func cost(of spell: ResolvedSpell, caster: ActorValueHolder) -> Float {
        let skill = spell.magicSkill.flatMap { values.value(at: $0, on: caster) } ?? 0
        let authored = Float(spell.cost.cost)
            * costSettings.skillMultiplier(skill: skill, isPlayer: caster.key == .player)
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
        perks.conditions.spellEvaluation = SpellEvaluationResolution(spell: spell)
        let outcome = perks.modify(
            cost,
            at: Self.spellCostEntryPoint,
            on: caster,
            subjects: PerkEvaluationSubjects(owner: caster.key)
                .binding(.spell, to: spellbook.spells.conditionSubject(of: spell)),
            actorValue: { [values] index in values.value(at: index, on: caster) }
        )
        perks.conditions.clear(SpellEvaluationResolution.self)
        // The tally advanced inside the copy, so hand it back rather than
        // dropping what the evaluation counted.
        self.perks = perks
        return max(0, outcome.value)
    }

    /// Whether `perk` already reduces spell cost through its own entry point,
    /// which is what makes the SPIT halving a duplicate rather than a second
    /// reduction. See the file header for the measured record.
    public static func reducesSpellCost(_ perk: ResolvedPerk) -> Bool {
        perk.effects.contains { $0.entryPoint == spellCostEntryPoint }
    }
}
