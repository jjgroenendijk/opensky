// The magic "Favorite" stats on the journal's Stats page: the spell, the school, and
// the shout the player used most. See docs/engine/statistics.md, Favourites.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
public import OpenSkyQuestsInterface

extension MagicCoordinator.MagicMenu {
    public func favoriteTexts(_ stats: MiscStatsState) -> [String: String] {
        FavoriteTexts(owner: self).favoriteTexts(stats)
    }
}

extension MagicCoordinator.MagicMenu {
    /// Builds the texts of the favourites menu.
    struct FavoriteTexts {
        let owner: MagicCoordinator.MagicMenu

        func favoriteTexts(_ stats: MiscStatsState) -> [String: String] {
            let coordinator = owner.coordinator
            let spells = coordinator.caster?.spellbook.spells
            let used = stats.recentUses[.spell] ?? []
            let schools = used.compactMap { key -> String? in
                guard
                    let spell = spells?.spell(key: key), spell.spellType == .spell,
                    let skill = spell.magicSkill
                else { return nil }
                return ActorValueIdentity.name(at: skill)
            }
            let texts: [String: String?] = [
                FavoriteUse.spell.statName: MiscStats.favorite(of: used)
                    .flatMap { spells?.spell(key: $0)?.displayName },
                MiscStats.favoriteSchool: MiscStats.favorite(of: schools),
                FavoriteUse.shout.statName: MiscStats.favorite(of: stats.recentUses[.shout] ?? [])
                    .flatMap { coordinator.shouts[$0]?.displayName }
            ]
            return texts.compactMapValues { $0.flatMap { $0.isEmpty ? nil : $0 } }
        }
    }
}
