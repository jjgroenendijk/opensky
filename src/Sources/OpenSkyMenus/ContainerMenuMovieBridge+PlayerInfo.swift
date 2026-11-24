// The player half of the bottom bar: the barter movie's `PlayerInfoObj`, which its
// `UpdateItemCardInfo` hands to `BottomBar.SetBarterPerItemInfo` beside the item.
// See docs/engine/barter.md#the-item-card.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyFormatsSWF
public import OpenSkyInventoryInterface

nonisolated extension ContainerMenuMovieBridge {
    /// `BarterMenu.PlayerInfoObj`, which `UpdatePlayerInfo` stores.
    public static let playerInfoObjectName = "PlayerInfoObj"

    /// The `damage` and `armor` the bar shows: the best equipped weapon's damage and
    /// the worn armour's summed rating plus the armour bonus, after skill and perks.
    public static func playerInfo(
        of entries: [InventoryMenuEntry],
        stats: ShownGearStats = .base,
        lookup: (FormID) -> InventoryItemCard?
    ) -> [String: AS2Value] {
        var damage = 0
        var armour = stats.armourBonus
        for entry in entries where entry.isEquipped {
            let card = InventoryMenuMovieBridge.card(for: entry, stats: stats, lookup: lookup)
            guard let card else { continue }
            damage = max(damage, card.damage ?? 0)
            armour += card.armourRating ?? 0
        }
        return ["damage": .number(Double(damage)), "armor": .number(Double(armour.rounded()))]
    }

    /// Stores `info` where the movie reads it; the next card update draws it.
    public static func publishPlayerInfo(_ info: [String: AS2Value], runtime: SWFMovieRuntime) {
        guard let menu = runtime.node(atPath: menuPath, from: runtime.root) else { return }
        let object = runtime.runtime.makeObject()
        for name in info.keys.sorted() {
            object.assign(info[name] ?? .undefined, for: name)
        }
        menu.object.assign(.object(object), for: playerInfoObjectName)
    }
}
