// World > Inventory & Equipment > Ownership: the `XOWN`/`XRNK` fields of the
// crosshair target. Read-only, because ownership is a fact about a placed
// reference.

import AppKit
import OpenSkyInventory

final class ItemOwnershipSection: PanelSectionViewController {
    weak var provider: (any InventoryEquipmentControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "ItemOwnershipStatsLabel"
    )

    override var sectionTitle: String {
        "Ownership"
    }

    override var sectionIdentifier: String {
        "itemOwnership"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        statsLabel.toolTip = "The owner of the crosshair target. Taking it is not stopped yet."
        return [
            statsLabel
        ]
    }

    override func refreshReadout() {
        guard let snapshot = provider?.inventoryEquipmentSnapshot else {
            statsLabel.stringValue = InventoryEquipmentSnapshot.unavailable.lastActionText
            return
        }
        statsLabel.stringValue = InventoryEquipmentReadout.ownershipText(for: snapshot)
    }
}
