// World > Inventory & Equipment > Ownership: the `XOWN`/`XRNK` reading for
// whatever the crosshair is on (issue #180, decoded in issue #175).
//
// Read-only by design, and it has no control at all. Ownership is not a setting
// a developer forces; it is a fact about a placed reference, and the only
// question worth answering is whether the take the panel above just did was
// theft. Nothing enforces it — a crime system is not in this milestone — so the
// readout says that too rather than letting silence imply enforcement.

import AppKit

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
