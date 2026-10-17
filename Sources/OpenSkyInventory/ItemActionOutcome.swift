// What the last item, crafting, grant, and trade action did, as values. Only the
// `text` formatters build lines; the shared sentences live in `InventoryCore`.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

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

    public var text: String {
        switch self {
        case .idle: "No item action yet."
        case .unavailable: InventoryCore.noRuntimeText
        case let .nothingUnderCrosshair(verb): "Nothing under the crosshair to \(verb)."
        case let .took(count, item): "Took \(count) × \(item)."
        case let .opened(container, items): "Opened \(container): \(items) items."
        case .noContainer: InventoryCore.noContainerText
        case let .tookAll(moved): InventoryCore.takeAllSentence(moved)
        case .closed: "Closed the container."
        case .nothingToDrop: "Nothing carried to drop."
        case .noDropCell: "Drop needs a resident cell; none is loaded."
        case let .dropped(count, item): "Dropped \(count) × \(item) in front of the player."
        case let .failed(action, reason): "\(action) failed: \(reason)"
        default: equipmentText
        }
    }

    private var equipmentText: String {
        switch self {
        case .noEquipment: InventoryCore.noEquipmentText
        case let .noEquipTarget(target): InventoryCore.noTargetText(target)
        case .nothingEquippable: "Nothing equippable held."
        case let .equipped(item, target, changed, unequipped):
            InventoryCore.equipSentence(
                changed: changed, item: item, target: target, unequipped: unequipped
            )
        case let .wearingNothing(target): "\(target) is wearing nothing."
        case let .unequipped(item, target, changed):
            changed
                ? "Unequipped \(item) on \(target)."
                : "\(item) was not equipped on \(target)."
        case let .harvested(plant, items):
            "Harvested \(plant): \(items.joined(separator: ", "))."
        case let .grewBack(plant): "\(plant) grew back."
        case let .script(change): change
        default: ""
        }
    }
}

nonisolated public enum CraftingActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    case noRecipeData
    case opened(station: String, recipes: Int)
    case noStationNamed(String)
    case notAStation(String)
    case notOpen
    case improved(item: String, from: String, to: String)
    case crafted(count: Int32, item: String)
    case craftFailed(reason: String)
    case closed

    public var text: String {
        switch self {
        case .idle: "No crafting action yet."
        case .unavailable: InventoryCore.noRuntimeText
        case .noRecipeData: "No recipe data is loaded."
        case let .opened(station, recipes): "Opened \(station): \(recipes) recipes."
        case let .noStationNamed(name): "No station named \(name)."
        case let .notAStation(name): "\(name) is no crafting station."
        case .notOpen: "No crafting station is open."
        case let .improved(item, from, to): "Improved \(item): \(from) -> \(to)."
        case let .crafted(count, item): "Crafted \(count) × \(item)."
        case let .craftFailed(reason): "Craft failed: \(reason)"
        case .closed: "Closed the crafting station."
        }
    }
}

nonisolated public enum GrantActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    case notAStack(count: Int32)
    case unknownItem(FormID)
    case noOpenContainer
    case granted(count: Int32, item: String, to: InventoryGrantTarget)
    case failed(reason: String)

    public var text: String {
        switch self {
        case .idle: "No grant yet."
        case .unavailable: "Inventory and equipment unavailable: no game data loaded."
        case let .notAStack(count): "Grant refused: a count of \(count) is not a stack."
        case let .unknownItem(item):
            "Grant refused: no loaded plugin describes \(item), so it has no "
                + "weight, value or name."
        case .noOpenContainer: "Grant refused: no container is open."
        case let .granted(count, item, target): "Granted \(count) × \(item) to \(target.label)."
        case let .failed(reason): "Grant failed: \(reason)"
        }
    }
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

    public func text(texts: TradeTexts) -> String {
        switch self {
        case .unavailable: InventoryCore.noRuntimeText
        case let .took(item, bounty): InventoryCore.takeSentence(item: item, bounty: bounty)
        case let .stored(item): "Stored \(item)."
        case .tooExpensive: texts.tooExpensive
        case let .bought(item, gold): "Bought \(item) for \(gold) gold."
        case let .merchantShort(price, gold): texts.merchantShortText(price: price, gold: gold)
        case let .sold(item, gold): "Sold \(item) for \(gold) gold."
        }
    }
}
