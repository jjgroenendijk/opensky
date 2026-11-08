// The caster's and the target's perks on each effect a cast spell lands: Mod Spell
// Magnitude, Mod Spell Duration, and Mod Incoming Spell Magnitude. A drunk potion
// takes the first two.
// See docs/engine/perk-entry-points.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension MagicCoordinator {
    /// `entries` of `spell`, cast by `caster`, as they land on `target`. A spell the
    /// spell store does not hold lands as authored.
    func perkScaled(
        _ entries: [MagicItemEffect],
        of spell: ReferenceKey,
        caster: ReferenceKey,
        on target: ReferenceKey
    ) -> [MagicItemEffect] {
        guard
            let spells = self.caster?.spellbook.spells,
            let resolved = spells.spell(key: spell)
        else { return entries }
        var seams = ConditionContext()
        seams.spellEvaluation = SpellEvaluationResolution(spell: resolved)
        return perkScaled(
            entries, subject: spells.conditionSubject(of: resolved), seams: seams,
            caster: caster, on: target
        )
    }

    /// `entries` of the potion `item` that `drinker` consumes. Catalyst tests the
    /// potion's effect keywords, so the potion binds as the spell subject.
    func perkScaledPotion(
        _ entries: [MagicItemEffect],
        of item: ReferenceKey,
        fromPlugin pluginName: String,
        drinker: ReferenceKey
    ) -> [MagicItemEffect] {
        guard let store = effects?.effects, case let .plugin(plugin, objectID) = item else {
            return entries
        }
        let keywords = entries.flatMap { entry in
            store.resolve(entry.effect, fromPlugin: pluginName)?.keywordKeys(in: store) ?? []
        }
        var seams = ConditionContext()
        seams.spellEvaluation = SpellEvaluationResolution(spell: nil, potionKeywords: Set(keywords))
        return perkScaled(
            entries,
            subject: ConditionFormSubject(
                id: ResolvedFormID(plugin: plugin, objectID: objectID),
                effectKeywords: Set(keywords)
            ),
            seams: seams,
            caster: drinker,
            on: nil
        )
    }

    /// A nil `target` skips Mod Incoming Spell Magnitude, which no potion takes:
    /// the Atronach Stone's unconditioned half would halve every drink.
    private func perkScaled(
        _ entries: [MagicItemEffect],
        subject: ConditionFormSubject,
        seams: ConditionContext,
        caster: ReferenceKey,
        on target: ReferenceKey?
    ) -> [MagicItemEffect] {
        let cast = PerkEvaluationSubjects(owner: caster, target: target ?? caster)
            .binding(.spell, to: subject)
        return entries.map { entry in
            var magnitude = world.perkModified(
                entry.magnitude, at: .modSpellMagnitude, on: caster, subjects: cast, seams: seams
            )
            if let target {
                magnitude = world.perkModified(
                    magnitude,
                    at: .modIncomingSpellMagnitude,
                    on: target,
                    subjects: PerkEvaluationSubjects(owner: target).binding(.spell, to: subject),
                    seams: seams
                )
            }
            let duration = world.perkModified(
                Float(entry.duration), at: .modSpellDuration, on: caster, subjects: cast,
                seams: seams
            )
            return entry.with(magnitude: magnitude, duration: duration)
        }
    }
}
