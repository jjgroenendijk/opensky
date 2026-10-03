// The visual links of the abilities a race grants, such as a glow or a lasting
// membrane. See docs/rendering/visual-effects.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

extension MagicCoordinator {
    /// The hit-shader and art links of each `SPLO` spell on the race of `base`.
    public func raceEffectLinks(base: FormID, actor: ReferenceKey) -> [SpellHitEffectLinks] {
        guard
            let caster, let spellBaselines, let spellPluginName,
            let store = effects?.effects
        else {
            return []
        }
        let spells = spellBaselines.baseline(for: base).raceSpells
        return caster.spellbook.resolve(spells, fromPlugin: spellPluginName).flatMap { key in
            caster.spellbookAccess.record(key).map {
                store.hitEffectLinks(of: $0.payload(caster: actor))
            } ?? []
        }
    }
}
