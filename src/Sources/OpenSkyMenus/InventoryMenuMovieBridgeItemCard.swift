// The item card half of the inventory movie: `ItemCard_mc.itemInfo`, filled through the
// `UpdateItemCardInfo` callback the menu registers with `GameDelegate`. The field names
// and the `ICT_` numbers were read from the installed movie's `InventoryDefines`.
// See docs/engine/inventory-menu.md#item-card.

import Foundation
public import OpenSkyFormatsSWF
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface

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

    /// Sends the selected row's card to the movie, or hides the card with no row. A
    /// `charge` in percent fills the weapon's meter, which the Charge button reads.
    public static func publishItemCard(
        _ card: InventoryItemCard?, charge: Float? = nil, runtime: SWFMovieRuntime
    ) {
        var info = card.map(itemCardInfo) ?? ["type": .integer(0)]
        if card != nil, let charge {
            info["charge"] = .number(Double(charge))
        }
        send(info, runtime: runtime)
    }

    /// `ICT_LIST`: the card becomes a list of soul gems, each with the charge it adds.
    public static func publishSoulGemList(
        _ offer: RechargeOffer, title: String, runtime: SWFMovieRuntime
    ) {
        let rows = offer.gems.map { gem in
            let row = runtime.runtime.makeObject()
            row.assign(.string(gem.name), for: "text")
            row.assign(.number(Double(gem.addedPercent)), for: "chargeAdded")
            return AS2Value.object(row)
        }
        send([
            "type": .integer(soulGemListType),
            "name": .string(title),
            "currentCharge": .number(Double(offer.currentPercent)),
            "listItems": .object(runtime.runtime.makeArray(rows))
        ], runtime: runtime)
    }

    /// `ICT_LIST` in the movie's `InventoryDefines`.
    public static let soulGemListType = 14

    private static func send(_ info: [String: AS2Value], runtime: SWFMovieRuntime) {
        let object = runtime.runtime.makeObject()
        for name in info.keys.sorted() {
            object.assign(info[name] ?? .undefined, for: name)
        }
        runtime.callMovie(itemCardCallback, arguments: [.object(object)])
    }
}
