// The magic and gift menus' rows and actions: known spells from the magic coordinator,
// and gift items moved between the player and an actor's inventory.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus

extension MenuScreensWorldAdapter: MagicMenuWorld {
    /// "All" first, then one tab per spell kind in the order the kinds first appear.
    var magicMenuCategories: [ItemListCategory] {
        let spells = game.magic.magicMenuSpells.enumerated().map { index, spell in
            (kind: spell.typeName, row: ItemListRow(
                tag: UInt32(index), name: spell.name, isEquipped: spell.isReadied
            ))
        }
        var kinds: [String] = []
        for spell in spells where !kinds.contains(spell.kind) {
            kinds.append(spell.kind)
        }
        return [ItemListCategory(label: "All", rows: spells.map(\.row))] + kinds.map { kind in
            ItemListCategory(label: kind, rows: spells.filter { $0.kind == kind }.map(\.row))
        }
    }

    func readySpell(at index: Int, leftHand: Bool) -> String {
        game.magic.readyKnownSpell(at: index, in: leftHand ? .left : .right).text
    }
}

extension MenuScreensWorldAdapter: GiftMenuWorld {
    var nearestActor: ReferenceKey? {
        game.actorWorld.nearestActorValueHolder()?.key
    }

    func giftCategories(actor: ReferenceKey, giving: Bool) -> [ItemListCategory] {
        guard
            let runtime = game.inventory.runtime?.inventory,
            let giver = giving ? .player : game.streamer?.inventoryHolder(of: actor)
        else { return [] }
        let rows = runtime.inventory(of: giver).stacks
            .filter { $0.item != runtime.goldFormID }
            .map { stack in
                ItemListRow(
                    tag: stack.item.rawValue, name: game.inventory.name(of: stack.item),
                    count: stack.count
                )
            }
            .sorted { $0.name < $1.name }
        return [ItemListCategory(label: "All", rows: rows)]
    }

    func give(_ item: FormID, actor: ReferenceKey, giving: Bool) -> String {
        guard
            let runtime = game.inventory.runtime?.inventory,
            let other = game.streamer?.inventoryHolder(of: actor)
        else { return "No inventory" }
        let name = game.inventory.name(of: item)
        do {
            try runtime.transfer(
                item, count: 1, from: giving ? .player : other, to: giving ? other : .player
            )
            return giving ? "Gave \(name)" : "Received \(name)"
        } catch {
            return "Not moved: \(error)"
        }
    }
}
