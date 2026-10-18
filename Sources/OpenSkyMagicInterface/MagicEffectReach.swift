// The effects a spell affecting an actor can apply, which `HasMagicEffect` tests
// (<https://ck.uesp.net/wiki/HasMagicEffect>).

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public enum MagicEffectReach {
    /// MGEFs of the spells acting on an actor: the sources of its active effects, and
    /// the abilities, diseases and addictions it carries, whose effects can be off
    /// while their conditions fail.
    public static func potentialEffects(
        known: some Sequence<ReferenceKey>,
        sources: some Sequence<ReferenceKey>,
        record: (ReferenceKey) -> ResolvedSpell?
    ) -> Set<ReferenceKey> {
        var spells = Set(sources)
        for spell in known where isCarried(record(spell)?.spellType) {
            spells.insert(spell)
        }
        return spells.reduce(into: []) { effects, spell in
            for effect in record(spell)?.effects ?? [] {
                if let key = effect.effect?.key {
                    effects.insert(key)
                }
            }
        }
    }

    private static func isCarried(_ type: SpellType?) -> Bool {
        switch type {
        case .ability, .disease, .addiction: true
        default: false
        }
    }
}
