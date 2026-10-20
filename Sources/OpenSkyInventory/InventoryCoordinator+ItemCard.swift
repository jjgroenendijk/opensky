// The inventory menu's item card for one carried item. See docs/engine/inventory-menu.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

extension InventoryCoordinator {
    /// Nil without game data or for an item no plugin describes.
    public func itemCard(for item: FormID) -> InventoryItemCard? {
        guard
            let runtime,
            let definition = runtime.inventory.baselines.items.definition(item)
        else {
            return nil
        }
        let items = runtime.inventory.baselines.items
        let favourites = playerFavourites
        return InventoryItemCard(
            item: item,
            layout: Self.layout(of: definition, items: items),
            name: name(of: item),
            kind: Self.kind(of: definition, items: items),
            value: items.gameValue(of: item),
            weight: definition.weight,
            damage: items.weapons[item.rawValue].map { Int($0.damage) },
            // DNAM holds the rating times 100.
            armourRating: items.armor[item.rawValue].map { Float($0.armorRating & 0xFFFF) / 100 },
            effects: effectLines(of: item, items: items),
            enchantment: world.enchantmentLine(of: item, on: runtime.player.key),
            isStolen: runtime.inventory.inventory(of: runtime.player).stolenCount(of: item) > 0,
            hotkey: favourites.hotkey(of: item),
            isFavourite: favourites.contains(item)
        )
    }

    private func effectLines(of item: FormID, items: ItemDefinitionStore) -> [String] {
        if let ingredient = items.ingredients[item.rawValue] {
            let knowledge = ingredientKnowledge
            return ingredient.effects.indices.map { index in
                knowledge.knows(index, of: item) ? effectName(ingredient.effects[
                    index
                ].effect) : "?"
            }
        }
        let effects = items.ingestibles[item.rawValue]?.effects
            ?? items.scrolls[item.rawValue]?.effects ?? []
        return effects.map { entry in
            var line = effectName(entry.effect)
            if entry.magnitude > 0 {
                line += " \(Int(entry.magnitude.rounded()))"
            }
            if entry.duration > 0 {
                line += " for \(entry.duration) s"
            }
            return line
        }
    }

    private static func layout(of definition: ItemDefinition, items: ItemDefinitionStore)
        -> InventoryItemCard.Layout
    {
        switch definition.family {
        case .armor: .armour
        case .weapon, .ammunition: .weapon
        case .book: .book
        case .ingestible:
            items.ingestibles[definition.formID.rawValue]?.flags.contains(.food) == true
                ? .food : .potion
        case .scroll: .potion
        case .ingredient: .ingredient
        case .key: .key
        case .soulGem: .soulGem
        case .miscellaneous, .apparatus: .misc
        }
    }

    private static func kind(of definition: ItemDefinition, items: ItemDefinitionStore) -> String {
        switch definition.family {
        case .armor: "Armour"
        case .ammunition: "Ammunition"
        case .apparatus: "Apparatus"
        case .book: items.teachesSpell(definition.formID) != nil ? "Spell tome" : "Book"
        case .ingestible:
            items.ingestibles[definition.formID.rawValue].map { potion in
                potion.flags.contains(.food) ? "Food"
                    : potion.flags.contains(.poison) ? "Poison" : "Potion"
            } ?? "Potion"
        case .ingredient: "Ingredient"
        case .key: "Key"
        case .miscellaneous: "Misc"
        case .scroll: "Scroll"
        case .soulGem: "Soul gem"
        case .weapon: "Weapon"
        }
    }
}
