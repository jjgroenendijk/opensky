// World > Inventory & Equipment. Sections follow the loop: place an item, ask
// who owns the target, see what an equip did to an actor, then make and gather
// items at a station or a plant. Take, drop, and
// equip live under `World > HUD & Interaction > Items`; barter lives under
// `World > Container Menu`. One control has one sidebar path.

import AppKit
import OpenSkyInventory

final class InventoryEquipmentPanelViewController: InspectorPanelViewController {
    let grantsSection = InventoryGrantsSection()
    let ownershipSection = ItemOwnershipSection()
    let equipmentSection = EquipmentInspectionSection()
    let craftingSection = CraftingSection()
    let harvestSection = HarvestSection()

    /// Live bridge. Weak: the game controller owns this panel's parent and the
    /// item runtime, so the panel must not retain back.
    weak var provider: (any InventoryEquipmentControlProviding)? {
        didSet {
            grantsSection.provider = provider
            ownershipSection.provider = provider
            equipmentSection.provider = provider
        }
    }

    weak var craftingProvider: (any CraftingControlProviding)? {
        didSet {
            craftingSection.provider = craftingProvider
            harvestSection.provider = craftingProvider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [grantsSection, ownershipSection, equipmentSection, craftingSection, harvestSection]
    }
}
