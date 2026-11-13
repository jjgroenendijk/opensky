// The crafting menu at an arcane enchanter: four tabs, the item to destroy, and the
// item, enchantments, and soul gem to combine. A destroy and a make each ask first.
// See docs/engine/enchanting.md#enchanting-menu.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenusInterface

/// The enchanting tabs' rows and what the player chose on them.
struct CraftingMenuEnchanting {
    private enum Pick {
        case destroy(FormID)
        case item(FormID)
        case base(ReferenceKey)
        case gem(EnchanterGem)
    }

    private(set) var selection = EnchanterSelection()
    private var picks: [Pick] = []

    /// Disenchant, Item, Enchantment, and Soul Gem, in the game's order. A chosen row
    /// shows as equipped.
    mutating func categories(
        _ choices: EnchanterChoices, texts: GameSettingTexts<EnchantingMenuText>
    ) -> [ItemListCategory] {
        if let item = selection.item, !choices.enchantable.contains(where: { $0.id == item }) {
            selection.item = nil
        }
        if let gem = selection.gem, !choices.gems.contains(gem) {
            selection.gem = nil
        }
        picks = []
        func rows(_ entries: [(Pick, String, Bool)]) -> [ItemListRow] {
            entries.map { pick, name, chosen in
                picks.append(pick)
                return ItemListRow(tag: UInt32(picks.count - 1), name: name, isEquipped: chosen)
            }
        }
        let destroy = rows(choices.disenchantable.map { (.destroy($0.id), $0.name, false) })
        let items = rows(choices.enchantable.map { (.item($0.id), $0.name, $0.id == selection.item) })
        let bases = rows(choices.enchantments.map {
            (.base($0.key), $0.name, selection.bases.contains($0.key))
        })
        let gems = rows(choices.gems.map { (.gem($0), $0.name, $0 == selection.gem) })
        return [
            ItemListCategory(label: texts[.disenchant], rows: destroy),
            ItemListCategory(label: texts[.item], rows: items),
            ItemListCategory(label: texts[.enchantment], rows: bases),
            ItemListCategory(label: texts[.soulGem], rows: gems)
        ]
    }

    /// The accept key destroys or chooses the row; the second key makes the item.
    mutating func choose(
        _ row: ItemListRow, alternate: Bool, world: any CraftingMenuWorld,
        changed: @escaping () -> Void
    ) -> String {
        if alternate {
            return make(world: world, changed: changed)
        }
        guard picks.indices.contains(Int(row.tag)) else { return "No row" }
        switch picks[Int(row.tag)] {
        case let .destroy(item):
            let texts = world.enchantingTexts
            world.confirm(texts[.confirmDisenchant]) { yes in
                guard yes else { return }
                let answer = world.disenchant(item)
                if answer.done {
                    world.inform(answer.text)
                } else {
                    world.showHUDNotification(answer.text)
                }
                changed()
            }
            return "Asked to destroy \(row.name)"
        case let .item(item):
            selection.item = selection.item == item ? nil : item
        case let .base(key):
            if let index = selection.bases.firstIndex(of: key) {
                selection.bases.remove(at: index)
            } else {
                selection.bases.append(key)
            }
        case let .gem(gem):
            selection.gem = selection.gem == gem ? nil : gem
        }
        return "Chose \(row.name)"
    }

    /// Names the item to make; nil or empty keeps the made name.
    mutating func rename(_ name: String?) {
        selection.name = name.flatMap { $0.isEmpty ? nil : $0 }
    }

    private mutating func make(world: any CraftingMenuWorld, changed: @escaping () -> Void) -> String {
        if let refusal = world.enchantRefusal(selection) {
            world.showHUDNotification(refusal)
            return refusal
        }
        let chosen = selection
        selection = EnchanterSelection()
        world.confirm(world.enchantingTexts[.confirmEnchant]) { yes in
            guard yes else { return }
            let answer = world.enchant(chosen)
            if !answer.done {
                world.showHUDNotification(answer.text)
            }
            changed()
        }
        return "Asked to enchant"
    }
}
