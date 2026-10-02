// World > Inventory & Equipment > Grants: puts a known item in a known
// inventory, so the take, transfer, equip, buy, sell and drop loop is
// repeatable. A developer-only action that creates items; the readout says what.
// No override: World > Runtime State owns resetting world changes.

import AppKit
import OpenSkyInventory

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
        grantControl.toolTip = "Creates the items in the inventory."
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
            statsLabel.stringValue = "Grant refused: FormID must be hexadecimal."
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
