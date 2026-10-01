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
        [
            PanelComponents.note(
                "The owning NPC_ or FACT of the reference under the walk-mode crosshair, "
                    + "straight off its XOWN field, with the XRNK faction rank when one is "
                    + "authored. Reported only: taking an owned item is theft in the data "
                    + "and nothing in the engine stops it yet."
            ),
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
