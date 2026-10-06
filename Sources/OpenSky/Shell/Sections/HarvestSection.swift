// World > Inventory & Equipment > Harvest: the crosshair plant's produce, harvested
// state, and regrowth time, with a forced harvest and a forced regrowth.

import AppKit
import OpenSkyInventory

final class HarvestSection: PanelSectionViewController {
    weak var provider: (any CraftingControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let harvestControl = NSButton(title: "Harvest", target: nil, action: nil)
    let resetControl = NSButton(title: "Grow back", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "HarvestStatsLabel")

    override var sectionTitle: String {
        "Harvest"
    }

    override var sectionIdentifier: String {
        "harvest"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        harvestControl.toolTip = "Harvests the plant under the crosshair."
        PanelComponents.configureButton(
            harvestControl, target: self, action: #selector(harvest),
            identifier: "HarvestForceControl"
        )
        resetControl.toolTip = "Makes the plant under the crosshair grow back now."
        PanelComponents.configureButton(
            resetControl, target: self, action: #selector(reset),
            identifier: "HarvestResetControl"
        )
        return [PanelComponents.buttonRow([harvestControl, resetControl]), statsLabel]
    }

    override func syncControls() {
        harvestControl.isEnabled = provider != nil
        resetControl.isEnabled = provider != nil
    }

    override func refreshReadout() {
        statsLabel.stringValue = CraftingReadout.harvestText(
            for: provider?.craftingSnapshot ?? .unavailable
        )
    }

    @objc private func harvest() {
        provider?.forceHarvest()
        finishInteraction()
    }

    @objc private func reset() {
        provider?.resetHarvest()
        finishInteraction()
    }
}
