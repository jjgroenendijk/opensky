// The one spell that waits for the other hand: a self Invisibility spell, as observed
// in the game. See docs/engine/spellcasting.md#what-refuses-a-cast.

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated enum MultiCastRule {
    /// True when `spell` may not start while the other hand is casting.
    static func refuses(_ spell: ResolvedSpell, otherHandCasting: Bool) -> Bool {
        guard otherHandCasting, (spell.data?.delivery ?? .selfTarget) == .selfTarget else {
            return false
        }
        return spell.effects.contains { $0.effect?.effect.data?.archetype == .invisibility }
    }
}
