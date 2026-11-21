// The magic stats on the journal's Stats page. See docs/engine/statistics.md.

import OpenSkyFormatsESM
import OpenSkyQuestsInterface

extension MagicCoordinator {
    /// Raises a journal stat in the session's store. A session without one counts nothing.
    func incrementStat(_ name: String) {
        (effects?.store ?? caster?.spellbook.store)?.incrementMiscStat(name)
    }

    func noteFavoriteUse(_ use: FavoriteUse, of form: ReferenceKey) {
        (effects?.store ?? caster?.spellbook.store)?.noteFavoriteUse(use, of: form)
    }

    /// Spells, powers, lesser powers, and abilities count for Favorite Spell; diseases,
    /// poisons, addictions, and shouts do not (docs/engine/statistics.md, Favourites).
    static func countsForFavoriteSpell(_ type: SpellType) -> Bool {
        switch type {
        case .spell, .power, .lesserPower, .ability: true
        default: false
        }
    }
}
