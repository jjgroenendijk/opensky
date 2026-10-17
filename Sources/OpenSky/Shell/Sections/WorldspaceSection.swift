// World > World > Worldspace: the worldspace and cell the player is in, and a
// jump to any exterior cell of any worldspace.

import AppKit
import OpenSkyWorld

final class WorldspaceSection: PanelSectionViewController {
    weak var provider: (any WorldspaceControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let worldspaceControl = NSPopUpButton()
    let xControl = NSTextField()
    let yControl = NSTextField()
    let goControl = NSButton(title: "Go", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "WorldspaceStatsLabel")
    private var names: [String] = []
    private var lastText = "Last: none"

    override var sectionTitle: String {
        "Worldspace"
    }

    override var sectionIdentifier: String {
        "worldspace"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            worldspaceControl, target: self, action: #selector(selectWorldspace),
            identifier: "WorldspacePickControl", width: 220
        )
        worldspaceControl.toolTip = "The worldspace to go to"
        PanelComponents.configureTextField(
            xControl, identifier: "WorldspaceXControl", width: 60, placeholder: "X"
        )
        PanelComponents.configureTextField(
            yControl, identifier: "WorldspaceYControl", width: 60, placeholder: "Y"
        )
        xControl.toolTip = "The grid X of the exterior cell"
        yControl.toolTip = "The grid Y of the exterior cell"
        goControl.toolTip = "Moves the player to the cell, behind a loading screen"
        PanelComponents.configureButton(
            goControl, target: self, action: #selector(go), identifier: "WorldspaceGoControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "World", captionWidth: 60, field: worldspaceControl
                ),
                PanelComponents.buttonRow([xControl, yControl, goControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let current = provider?.worldspaceNames ?? []
        if current != names {
            names = current
            worldspaceControl.removeAllItems()
            worldspaceControl.addItems(withTitles: names)
            if let world = provider?.currentWorldspace {
                worldspaceControl.selectItem(withTitle: world)
            }
        }
        worldspaceControl.isEnabled = !names.isEmpty
        goControl.isEnabled = !names.isEmpty
    }

    override func refreshReadout() {
        syncControls()
        statsLabel.stringValue = WorldspaceReadout.text(
            worldspace: provider?.currentWorldspace, cell: provider?.worldspacePlayerCell,
            last: lastText
        )
    }

    @objc private func selectWorldspace() {
        finishInteraction()
    }

    @objc private func go() {
        guard let world = worldspaceControl.titleOfSelectedItem else { return }
        let text = { (field: NSTextField) in
            field.stringValue.trimmingCharacters(in: .whitespaces)
        }
        guard let x = Int32(text(xControl)), let y = Int32(text(yControl)) else {
            lastText = "Last: X and Y must be whole numbers"
            refreshReadout()
            return
        }
        provider?.goToExterior(worldspace: world, x: x, y: y)
        lastText = "Last: \(world) \(x), \(y)"
        refreshReadout()
        finishInteraction()
    }
}
