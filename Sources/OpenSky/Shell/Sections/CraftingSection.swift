// World > Inventory & Equipment > Crafting: opens a station by name, lists its
// recipes with a verdict each, and crafts one.

import AppKit
import OpenSkyFormatsESM
import OpenSkyInventory

final class CraftingSection: PanelSectionViewController {
    weak var provider: (any CraftingControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let stationControl = NSPopUpButton()
    let openControl = NSButton(title: "Open", target: nil, action: nil)
    let closeControl = NSButton(title: "Close", target: nil, action: nil)
    let recipeControl = NSPopUpButton()
    let craftControl = NSButton(title: "Craft", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "CraftingStatsLabel")
    private var recipeIDs: [ResolvedFormID] = []

    override var sectionTitle: String {
        "Crafting"
    }

    override var sectionIdentifier: String {
        "crafting"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            stationControl, target: self, action: #selector(noAction),
            identifier: "CraftingStationControl", width: 260
        )
        PanelComponents.configurePopUp(
            recipeControl, target: self, action: #selector(noAction),
            identifier: "CraftingRecipeControl", width: 260
        )
        openControl.toolTip = "Uses the station as if the player stood at it."
        PanelComponents.configureButton(
            openControl, target: self, action: #selector(openStation),
            identifier: "CraftingOpenControl"
        )
        PanelComponents.configureButton(
            closeControl, target: self, action: #selector(closeStation),
            identifier: "CraftingCloseControl"
        )
        craftControl.toolTip = "Uses up the parts and makes the item, or improves a held one."
        PanelComponents.configureButton(
            craftControl, target: self, action: #selector(craft),
            identifier: "CraftingCraftControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Station", captionWidth: 60, field: stationControl
                ),
                PanelComponents.buttonRow([openControl, closeControl]),
                PanelComponents.labeledFieldRow(
                    caption: "Recipe", captionWidth: 60, field: recipeControl
                ),
                PanelComponents.buttonRow([craftControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let snapshot = provider?.craftingSnapshot ?? .unavailable
        if stationControl.itemTitles != snapshot.stations {
            stationControl.removeAllItems()
            stationControl.addItems(withTitles: snapshot.stations)
        }
        openControl.isEnabled = !snapshot.stations.isEmpty
        syncRecipes(snapshot)
    }

    override func refreshReadout() {
        let snapshot = provider?.craftingSnapshot ?? .unavailable
        syncRecipes(snapshot)
        statsLabel.stringValue = CraftingReadout.craftingText(for: snapshot)
    }

    private func syncRecipes(_ snapshot: CraftingControlSnapshot) {
        let ids = snapshot.recipes.map(\.id)
        if ids != recipeIDs {
            recipeIDs = ids
            recipeControl.removeAllItems()
            recipeControl.addItems(withTitles: snapshot.recipes.map(\.name))
        }
        closeControl.isEnabled = snapshot.stationName != nil
        craftControl.isEnabled = !recipeIDs.isEmpty
    }

    // MARK: - Actions

    @objc private func noAction() {}

    @objc private func openStation() {
        guard let title = stationControl.titleOfSelectedItem else { return }
        provider?.openCraftingStation(title)
        finishInteraction()
    }

    @objc private func closeStation() {
        provider?.closeCraftingStation()
        finishInteraction()
    }

    @objc private func craft() {
        let index = recipeControl.indexOfSelectedItem
        guard recipeIDs.indices.contains(index) else { return }
        provider?.craftRecipe(recipeIDs[index])
        finishInteraction()
    }
}
