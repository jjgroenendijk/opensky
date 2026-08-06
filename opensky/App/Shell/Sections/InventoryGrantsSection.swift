// World > Inventory & Equipment > Grants: the M12 gate's starting state
// (issue #180).
//
// The loop the gate proves — take, transfer, equip, buy, sell, drop — needs a
// known item in a known inventory before any of it can run. Without this
// control that means finding one in the world by hand, which is not repeatable
// and not something an acceptance record can name. Granting is a developer
// action with no analogue in the shipping game, and it is stated as one: it
// creates items, so it is the one operation in this milestone that is not
// conservation-preserving, and the readout says what it created.
//
// It carries no override state, for the same reason `ItemsSection` carries
// none: a grant is a world change recorded in `WorldStateStore`, and
// `World > Runtime State` already owns resetting those. A second reset here
// would give the same deltas two owners.

import AppKit

final class InventoryGrantsSection: PanelSectionViewController {
    weak var provider: (any InventoryEquipmentControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let formIDField = NSTextField(string: "")
    let countField = NSTextField(string: "1")
    let targetControl = NSSegmentedControl(
        labels: InventoryGrantTarget.allCases.map(\.label),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    let grantControl = NSButton(title: "Grant", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "InventoryGrantsStatsLabel"
    )

    override var sectionTitle: String {
        "Grants"
    }

    override var sectionIdentifier: String {
        "inventoryGrants"
    }

    var readout: String {
        statsLabel.stringValue
    }

    /// Where the grant lands, defaulting to the player: that is where the loop
    /// starts, and it is the one target that always resolves.
    var grantTarget: InventoryGrantTarget {
        let index = targetControl.selectedSegment
        guard InventoryGrantTarget.allCases.indices.contains(index) else { return .player }
        return InventoryGrantTarget.allCases[index]
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureTextField(
            formIDField, identifier: "InventoryGrantFormIDField", width: 150,
            placeholder: "hex FormID"
        )
        PanelComponents.configureTextField(
            countField, identifier: "InventoryGrantCountField", width: 60
        )
        targetControl.setAccessibilityIdentifier("InventoryGrantTargetControl")
        targetControl.selectedSegment = 0
        PanelComponents.configureButton(
            grantControl, target: self, action: #selector(grant),
            identifier: "InventoryGrantControl"
        )
        return [
            PanelComponents.note(
                "Grant puts items into an inventory outright, so the milestone loop can "
                    + "start from a known state without hunting the world for one. It is a "
                    + "developer action: unlike every other operation here it creates items "
                    + "rather than moving them. Open container needs a session from "
                    + "World > HUD & Interaction > Items, and is the same inventory a "
                    + "nominated merchant barters from."
            ),
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "FormID", captionWidth: 60, field: formIDField
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Count", captionWidth: 60, field: countField
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Into", captionWidth: 60, field: targetControl
                )
            ]),
            PanelComponents.buttonRow([grantControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        grantControl.isEnabled = provider != nil
    }

    override func refreshReadout() {
        guard let snapshot = provider?.inventoryEquipmentSnapshot else {
            statsLabel.stringValue = InventoryEquipmentSnapshot.unavailable.lastActionText
            return
        }
        statsLabel.stringValue = InventoryEquipmentReadout.grantsText(for: snapshot)
    }

    // MARK: - Actions

    @objc private func grant() {
        guard let item = ItemsSection.parseFormID(formIDField.stringValue) else {
            statsLabel.stringValue = "Grant refused: type the item's FormID in hexadecimal."
            return
        }
        provider?.grantItem(item, count: count, to: grantTarget)
        finishInteraction()
    }

    /// The count field, floored at one: granting zero or minus three of
    /// something is never what the field meant.
    private var count: Int32 {
        max(1, Int32(countField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 1)
    }
}
