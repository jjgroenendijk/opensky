// World > Inventory & Equipment destination panel (issue #180): the M12
// milestone gate's own verification surface.
//
// It is a destination of its own rather than sections under an existing one
// because "Inventory & Equipment" is the milestone-named top-level path the
// gate calls for, which outranks the eight-control promotion threshold
// (docs/tools/app-ui.md, "Sectioned UI Lab and direct-content panels").
//
// Section order follows the order the gate's loop reaches for them: put an item
// somewhere, ask who owns what the crosshair is on, then look at what the
// equip actually did to an actor.
//
// The loop's other halves stay where they already are and are not duplicated
// here: take, search, take-all, drop, equip and unequip live under
// `World > HUD & Interaction > Items`, and merchant nomination plus buying and
// selling live under `World > Container Menu`. Two sidebar paths owning one
// control is worse than one path owning it and the acceptance record naming
// both.

import AppKit

final class InventoryEquipmentPanelViewController: InspectorPanelViewController {
    let grantsSection = InventoryGrantsSection()
    let ownershipSection = ItemOwnershipSection()
    let equipmentSection = EquipmentInspectionSection()

    /// Live bridge. Weak: the game controller owns this panel's parent and the
    /// item runtime, so the panel must not retain back.
    weak var provider: (any InventoryEquipmentControlProviding)? {
        didSet {
            grantsSection.provider = provider
            ownershipSection.provider = provider
            equipmentSection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [grantsSection, ownershipSection, equipmentSection]
    }
}
