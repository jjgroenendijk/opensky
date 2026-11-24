// The crafting menu at an arcane enchanter: four tabs, the item to destroy, and the
// item, enchantments, and soul gem to combine. A destroy and a make each ask first.
// See docs/engine/enchanting.md#enchanting-menu.

import OpenSkyFormatsESM
import OpenSkyFormatsSWF
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
    /// The slider the current choice offers, so a new maximum can reset the value.
    private(set) var slider: EnchanterSlider?
    private var sliderRequested = false
    private var picks: [Pick] = []
    private var known: Set<FormID> = []

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
        func rows(_ entries: [(pick: Pick, row: ItemListRow)]) -> [ItemListRow] {
            entries.map { entry in
                picks.append(entry.pick)
                var row = entry.row
                row.tag = UInt32(picks.count - 1)
                return row
            }
        }
        func row(_ name: String, chosen: Bool) -> ItemListRow {
            ItemListRow(tag: 0, name: name, isEquipped: chosen)
        }
        known = Set(choices.disenchantable.filter(\.isKnown).map(\.id))
        let destroy = rows(choices.disenchantable.map {
            (.destroy($0.id), row($0.name, chosen: false))
        })
        let items = rows(choices.enchantable.map {
            (.item($0.id), row($0.name, chosen: $0.id == selection.item))
        })
        let bases = rows(choices.enchantments.map {
            (.base($0.key), row($0.name, chosen: selection.bases.contains($0.key)))
        })
        let gems = rows(choices.gems.map { (.gem($0), row($0.name, chosen: $0 == selection.gem)) })
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
            let texts = world.enchanter.enchantingTexts
            guard !known.contains(item) else {
                world.showHUDNotification(texts[.alreadyKnown])
                return texts[.alreadyKnown]
            }
            world.confirm(texts[.confirmDisenchant]) { yes in
                guard yes else { return }
                let answer = world.enchanter.disenchant(item)
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
                sliderRequested = true
            }
        case let .gem(gem):
            selection.gem = selection.gem == gem ? nil : gem
        }
        offerSlider(world.enchanter)
        return "Chose \(row.name)"
    }

    /// The slider to open now: a base was just chosen and the choice has one.
    mutating func takeSliderRequest() -> EnchanterSlider? {
        defer { sliderRequested = false }
        return sliderRequested ? slider : nil
    }

    /// The movie's slider moved (`accepted` nil) or closed. A move previews the value; a
    /// close keeps it, and a cancel keeps the value from before.
    mutating func slide(
        to value: Int, accepted: Bool?, enchanter: any CraftingMenuEnchanter
    ) -> String {
        guard let current = slider else { return "No slider" }
        var probe = selection
        probe.magnitude = min(max(1, value), current.maximum)
        if accepted == true {
            selection = probe
        }
        slider = enchanter.enchantingSlider(accepted == nil ? probe : selection)
        guard let shown = slider else { return "No slider" }
        return "Magnitude \(shown.value) of \(shown.maximum), \(shown.uses) uses"
    }

    /// When the maximum changes, the chosen value jumps to the new maximum.
    private mutating func offerSlider(_ enchanter: any CraftingMenuEnchanter) {
        let offered = enchanter.enchantingSlider(selection)
        if offered?.maximum != slider?.maximum {
            selection.magnitude = nil
        }
        slider = enchanter.enchantingSlider(selection)
    }

    /// Something is chosen, so leaving asks first.
    var hasChoice: Bool {
        selection.item != nil || selection.gem != nil || !selection.bases.isEmpty
    }

    func isDestroyRow(_ row: ItemListRow) -> Bool {
        guard picks.indices.contains(Int(row.tag)), case .destroy = picks[Int(row.tag)] else {
            return false
        }
        return true
    }

    /// The longest name the game takes on PC (UESP "Skyrim:Enchanting").
    static let nameLimit = 32

    /// Names the item to make. A cancel, an empty name, or a character outside `allowed`
    /// keeps the name from before, with no message (docs/engine/enchanting.md).
    mutating func rename(_ name: String?, allowed: String? = nil) {
        guard let name, SWFFontConfig.accepts(name: name, allowed: allowed) else { return }
        selection.name = String(name.prefix(Self.nameLimit))
    }

    private mutating func make(
        world: any CraftingMenuWorld,
        changed: @escaping () -> Void
    ) -> String {
        if let refusal = world.enchanter.enchantRefusal(selection) {
            world.showHUDNotification(refusal)
            return refusal
        }
        let chosen = selection
        selection = EnchanterSelection()
        slider = nil
        world.confirm(world.enchanter.enchantingTexts[.confirmEnchant]) { yes in
            guard yes else { return }
            let answer = world.enchanter.enchant(chosen)
            if !answer.done {
                world.showHUDNotification(answer.text)
            }
            changed()
        }
        return "Asked to enchant"
    }
}
