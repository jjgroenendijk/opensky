// World > Inventory & Equipment > Equipment: what an owner wears, and why a
// piece added no geometry. Without this, a masked piece looks like an equip
// that did nothing. The owner selector picks the player or the nearest NPC.

import AppKit
import OpenSkyInventory

final class EquipmentInspectionSection: PanelSectionViewController {
    weak var provider: (any InventoryEquipmentControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let targetControl = NSSegmentedControl(
        labels: [
            InventoryEquipmentReadout.label(.player),
            InventoryEquipmentReadout.label(.nearestActor)
        ],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "EquipmentInspectionStatsLabel"
    )

    override var sectionTitle: String {
        "Equipment"
    }

    override var sectionIdentifier: String {
        "equipmentInspection"
    }

    var readout: String {
        statsLabel.stringValue
    }

    /// Which owner the section reads. Defaults to the NPC, because that is the
    /// one an equip shows on.
    var inspectionTarget: EquipmentTargetSelector {
        targetControl.selectedSegment == 0 ? .player : .nearestActor
    }

    override func makeContentViews() -> [NSView] {
        targetControl.setAccessibilityIdentifier("EquipmentInspectionTargetControl")
        targetControl.target = self
        targetControl.action = #selector(targetChanged)
        targetControl.selectedSegment = 1
        return [
            PanelComponents.note(
                "The owner's equipped set with the body slots and hands each piece claims, "
                    + "plus the reason-tagged appearance skips its cell's last build "
                    + "reported. A skip is not a failure: a skin part masked by an equipped "
                    + "cuirass is the outfit working. Equip and unequip themselves live "
                    + "under World > HUD & Interaction > Items."
            ),
            PanelComponents.labeledFieldRow(
                caption: "Owner", captionWidth: 60, field: targetControl
            ),
            statsLabel
        ]
    }

    override func syncControls() {
        guard let provider else { return }
        targetControl.selectedSegment =
            provider.inventoryEquipmentInspectionTarget == .player ? 0 : 1
    }

    override func refreshReadout() {
        guard let snapshot = provider?.inventoryEquipmentSnapshot else {
            statsLabel.stringValue = InventoryEquipmentSnapshot.unavailable.lastActionText
            return
        }
        statsLabel.stringValue = InventoryEquipmentReadout.equipmentText(for: snapshot)
    }

    @objc private func targetChanged() {
        provider?.inventoryEquipmentInspectionTarget = inspectionTarget
        finishInteraction()
    }

    // MARK: - Override state

    /// The documented default: the nearest NPC, which is the owner an equip is
    /// visible on.
    nonisolated static let defaultTarget = EquipmentTargetSelector.nearestActor

    override var isOverridden: Bool {
        provider.map { Self.isOverridden(provider: $0) } ?? false
    }

    override func resetToDefaults() {
        guard let provider else { return }
        Self.resetToDefaults(provider: provider)
    }

    /// Provider-backed query for the sidebar aggregation, which must answer
    /// without constructing an unopened panel.
    static func isOverridden(provider: any InventoryEquipmentControlProviding) -> Bool {
        provider.inventoryEquipmentInspectionTarget != defaultTarget
    }

    static func resetToDefaults(provider: any InventoryEquipmentControlProviding) {
        provider.inventoryEquipmentInspectionTarget = defaultTarget
    }
}
