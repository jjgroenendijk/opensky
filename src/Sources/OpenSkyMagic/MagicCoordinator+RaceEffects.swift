// The visual links of the abilities a race grants, such as a glow or a lasting
// membrane. See docs/rendering/visual-effects.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

extension MagicCoordinator.RaceEffects {
    /// The hit-shader and art links of each ability in the `SPLO` list of the
    /// race of `base`. A racial power, such as Dragonskin, shows its look only
    /// while it is cast, so it is left out.
    func raceEffectLinks(base: FormID, actor: ReferenceKey) -> [SpellHitEffectLinks] {
        guard
            let caster = coordinator.caster, let spellBaselines = coordinator.spellBaselines,
            let spellPluginName = coordinator.spellPluginName,
            let store = coordinator.effects?.effects
        else {
            return []
        }
        let spells = spellBaselines.baseline(for: base).raceSpells
        let resolved = caster.spellbook.resolve(spells, fromPlugin: spellPluginName)
        return resolved.flatMap { key -> [SpellHitEffectLinks] in
            guard
                let spell = caster.spellbookAccess.record(key),
                spell.record.data?.type == .ability
            else { return [] }
            return store.hitEffectLinks(of: spell.payload(caster: actor))
        }
    }
}
