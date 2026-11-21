// Which crafting stat one craft, temper, or brew raises. See
// docs/engine/statistics.md, Crafting.

public import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyQuestsInterface
import OpenSkyWorldState

nonisolated public enum CraftingStats {
    /// A forge or cooking craft, or a temper when `improved`. Nil for other items, such as
    /// an ingot or arrows.
    public static func stat(of family: ItemDefinition.Family?, improved: Bool) -> String? {
        switch (family, improved) {
        case (.weapon, true): "Weapons Improved"
        case (.armor, true): "Armor Improved"
        case (.weapon, false): "Weapons Made"
        case (.armor, false): "Armor Made"
        // Cooked food counts as a mixed potion.
        case (.ingestible, false): "Potions Mixed"
        default: nil
        }
    }

    public static func brewStat(isPoison: Bool) -> String {
        isPoison ? "Poisons Mixed" : "Potions Mixed"
    }

    @MainActor
    static func count(
        _ outcome: CraftOutcome,
        items: ItemDefinitionStore,
        in store: WorldStateStore
    ) {
        let family = items.definition(outcome.created.item)?.family
        if let stat = stat(of: family, improved: outcome.improved != nil) {
            store.incrementMiscStat(stat)
        }
    }

    /// A harvest's ingredients, one each, and a nirnroot also on its own stat. Crimson
    /// nirnroot is a different record and does not count as one.
    public static func harvestStats(
        of granted: [InventoryStack], items: ItemDefinitionStore
    ) -> [(name: String, count: Int32)] {
        granted.flatMap { stack -> [(name: String, count: Int32)] in
            guard let definition = items.definition(stack.item), definition.family == .ingredient
            else { return [] }
            let ingredient = ("Ingredients Harvested", stack.count)
            return definition.editorID == "Nirnroot"
                ? [ingredient, ("Nirnroots Found", stack.count)] : [ingredient]
        }
    }
}
