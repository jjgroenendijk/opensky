// The item card half of the inventory movie: `ItemCard_mc.itemInfo`, filled through the
// `UpdateItemCardInfo` callback the menu registers with `GameDelegate`. The field names
// and the `ICT_` numbers were read from the installed movie's `InventoryDefines`.
// See docs/engine/inventory-menu.md#item-card.

import Foundation
public import OpenSkyFormatsESM
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
            info["description"] = .string(card.description ?? "")
        default:
            // A weapon's or armour's own text replaces the enchantment text.
            if let description = card.description, !description.isEmpty {
                info["effects"] = .string(description)
            } else {
                let lines = card.effects + [card.enchantment].compactMap(\.self)
                info["effects"] = .string(lines.joined(separator: ", "))
            }
        }
        return info
    }

    /// The card of a row: the item's card, with the copy's own name and value when the
    /// row stands for one copy.
    public static func card(
        for entry: InventoryMenuEntry?,
        stats: ShownGearStats = .base,
        lookup: (FormID) -> InventoryItemCard?
    ) -> InventoryItemCard? {
        guard let entry, var card = lookup(entry.item) else { return nil }
        if entry.copy != nil {
            card.name = entry.name
            card.value = entry.value
        }
        return stats.applied(to: card, item: entry.item, temperLevel: entry.copy?.level ?? 0)
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

    /// A spell's card: `ICT_SPELL`, or `ICT_SPELL_DEFAULT` for a power, which shows no
    /// cost. A row with no card hides the card, as an empty list does. `soulSpent` on a
    /// shout plays the last unlocked word's `Learn` animation.
    public static func publishSpellCard(
        _ card: MagicMenuSpellCard?, name: String, soulSpent: Bool = false,
        runtime: SWFMovieRuntime
    ) {
        guard let card else {
            send(["type": .integer(0)], runtime: runtime)
            return
        }
        switch card.kind {
        case .power:
            send([
                "type": .integer(spellDefaultType), "name": .string(name),
                "effects": .string(card.effects)
            ], runtime: runtime)
        case .spell:
            send([
                "type": .integer(spellType), "name": .string(name),
                "effects": .string(card.effects), "spellCost": .integer(card.cost),
                // The movie shows the per-second cost layout when castTime is 0.
                "castTime": .integer(card.costIsPerSecond ? 0 : 1),
                "castLevel": .string(card.level)
            ], runtime: runtime)
        case let .shout(words):
            var info = shoutCardInfo(card, words: words, name: name)
            if soulSpent {
                info["soulSpent"] = .boolean(true)
            }
            send(info, runtime: runtime)
        case let .activeEffect(secondsLeft):
            // The movie hides the time when `timeRemaining` is 0.
            send([
                "type": .integer(activeEffectType), "name": .string(name),
                "effects": .string(card.effects), "timeRemaining": .integer(secondsLeft ?? 0)
            ], runtime: runtime)
        }
    }

    /// `word0` to `word2` hold the translation, `dragonWord0` to `dragonWord2` the dragon
    /// letters, and `unlocked0` to `unlocked2` whether the player unlocked the word.
    static func shoutCardInfo(
        _ card: MagicMenuSpellCard, words: [MagicMenuShoutWord], name: String
    ) -> [String: AS2Value] {
        var info: [String: AS2Value] = [
            "type": .integer(shoutType), "name": .string(name),
            "effects": .string(card.effects), "spellCost": .integer(card.cost)
        ]
        for (index, word) in words.prefix(3).enumerated() {
            info["word\(index)"] = .string(word.translation)
            info["dragonWord\(index)"] = .string(word.dragon)
            info["unlocked\(index)"] = .boolean(word.isUnlocked)
        }
        return info
    }

    /// `ICT_SPELL` and `ICT_SPELL_DEFAULT` in the movie's `InventoryDefines`.
    public static let spellType = 7
    public static let spellDefaultType = 13
    /// `ICT_SHOUT` and `ICT_ACTIVE_EFFECT` in the movie's `InventoryDefines`.
    public static let shoutType = 10
    public static let activeEffectType = 11

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
