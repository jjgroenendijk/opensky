// The item card half of the inventory movie: `ItemCard_mc.itemInfo`, filled through the
// `UpdateItemCardInfo` callback the menu registers with `GameDelegate`. The field names
// and the `ICT_` numbers were read from the installed movie's `InventoryDefines`.
// See docs/engine/inventory-menu.md#item-card.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyInventoryInterface

nonisolated extension InventoryMenuMovieBridge {
    public static let itemCardCallback = "UpdateItemCardInfo"

    /// The `ICT_` value of `InventoryDefines` that picks the card's page.
    public static func cardType(of layout: InventoryItemCard.Layout) -> Int {
        switch layout {
        case .armour: 1
        case .weapon: 2
        case .misc: 3
        case .book: 4
        case .food: 5
        case .potion: 6
        case .ingredient: 8
        case .key: 9
        case .soulGem: 12
        }
    }

    /// The `itemInfo` object for `card`. An ingredient lists its known effects as
    /// `itemEffect0` to `itemEffect3`; the movie shows `$UNKNOWN` for the rest.
    public static func itemCardInfo(_ card: InventoryItemCard) -> [String: AS2Value] {
        var info: [String: AS2Value] = [
            "type": .integer(cardType(of: card.layout)),
            "name": .string(card.name),
            "value": .integer(Int(card.value)),
            "weight": .number(Double(card.weight))
        ]
        if let damage = card.damage {
            info["damage"] = .integer(damage)
        }
        if let rating = card.armourRating {
            info["armor"] = .integer(Int(rating.rounded()))
        }
        switch card.layout {
        case .ingredient:
            info["numItemEffects"] = .integer(card.effects.count)
            for (index, effect) in card.effects.enumerated() where effect != "?" {
                info["itemEffect\(index)"] = .string(effect)
            }
        case .book:
            info["description"] = .string("")
        default:
            let lines = card.effects + [card.enchantment].compactMap(\.self)
            info["effects"] = .string(lines.joined(separator: ", "))
        }
        return info
    }

    /// Sends the selected row's card to the movie, or hides the card with no row.
    public static func publishItemCard(_ card: InventoryItemCard?, runtime: SWFMovieRuntime) {
        let info = card.map(itemCardInfo) ?? ["type": .integer(0)]
        let object = runtime.runtime.makeObject()
        for name in info.keys.sorted() {
            object.assign(info[name] ?? .undefined, for: name)
        }
        runtime.callMovie(itemCardCallback, arguments: [.object(object)])
    }
}
