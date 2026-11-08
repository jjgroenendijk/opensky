import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public enum ItemActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    /// `verb` names the use: "take", "search", "harvest", or "reset".
    case nothingUnderCrosshair(verb: String)
    case took(count: Int32, item: String)
    case opened(container: String, items: Int)
    case noContainer
    case tookAll([InventoryStack])
    case closed
    case nothingToDrop
    case noDropCell
    case dropped(count: Int32, item: String)
    case noEquipment
    case noEquipTarget(EquipmentTargetSelector)
    case nothingEquippable
    case equipped(item: String, target: String, changed: Bool, unequipped: [String])
    case wearingNothing(target: String)
    case unequipped(item: String, target: String, changed: Bool)
    case harvested(plant: String, items: [String])
    case grewBack(String)
    /// A Papyrus native changed an inventory; the value is the change in words.
    case script(String)
    /// `action` is the failed step's word, such as "Take" or "Search"; `reason` the
    /// thrown error's description.
    case failed(action: String, reason: String)
}

nonisolated public enum CraftingActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    case noRecipeData
    case opened(station: String, recipes: Int)
    case openedLab(String, ingredients: Int)
    case noStationNamed(String)
    case notAStation(String)
    case notOpen
    case improved(item: String, from: String, to: String)
    case crafted(count: Int32, item: String)
    case craftFailed(reason: String)
    case refused(CraftingRefusalText)
    case closed
}

/// One container-menu move. The two refusals read the load order's own notices.
nonisolated public enum TradeOutcome: Equatable, Sendable {
    case unavailable
    case took(item: String, bounty: Int32)
    case stored(String)
    case tooExpensive
    case bought(item: String, gold: Int32)
    case merchantShort(price: Int64, gold: Int32)
    case sold(item: String, gold: Int32)
    /// A quest item the player may not store or sell.
    case questItem
}
