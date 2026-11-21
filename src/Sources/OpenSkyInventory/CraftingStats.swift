// Which crafting stat one craft, temper, or brew raises. See
// docs/engine/statistics.md, Crafting.

public import OpenSkyGameData
import OpenSkyInventoryInterface
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
}
