// World > World > Traps: the trap triggers in the loaded cells with their script
// states, a forced fire and disarm on the selected one, its enable-parent chain,
// and the live hazards. Beside Triggers, because a trap is a trigger with a script.

import AppKit
import OpenSkyFormatsESM
import OpenSkyPhysics

final class TrapSection: PanelSectionViewController {
    weak var provider: (any TrapControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let trapControl = NSPopUpButton()
    let fireControl = NSButton(title: "Fire", target: nil, action: nil)
    let disarmControl = NSButton(title: "Disarm", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "TrapStatsLabel")
    private var trapKeys: [ReferenceKey] = []

    override var sectionTitle: String {
        "Traps"
    }

    override var sectionIdentifier: String {
        "traps"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        trapControl.toolTip = "Marks the trap in the world and shows its enable chain."
        PanelComponents.configurePopUp(
            trapControl, target: self, action: #selector(selectTrap),
            identifier: "TrapSelectControl", width: 260
        )
        fireControl.toolTip = "The player steps into the trigger and out again."
        PanelComponents.configureButton(
            fireControl, target: self, action: #selector(fire), identifier: "TrapFireControl"
        )
        disarmControl.toolTip = "The player presses the use key on the trap."
        PanelComponents.configureButton(
            disarmControl, target: self, action: #selector(disarm), identifier: "TrapDisarmControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Trap",
                    captionWidth: 60,
                    field: trapControl
                ),
                PanelComponents.buttonRow([fireControl, disarmControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let snapshot = provider?.trapSnapshot ?? .unavailable
        let keys = snapshot.triggers.map(\.key)
        if keys != trapKeys {
            trapKeys = keys
            trapControl.removeAllItems()
            trapControl.addItems(withTitles: snapshot.triggers.map(\.name))
        }
        if let selected = snapshot.selected, let index = trapKeys.firstIndex(of: selected) {
            trapControl.selectItem(at: index)
        }
        let hasTraps = !trapKeys.isEmpty
        trapControl.isEnabled = hasTraps
        fireControl.isEnabled = hasTraps
        disarmControl.isEnabled = hasTraps
    }

    override func refreshReadout() {
        syncControls()
        statsLabel.stringValue = TrapReadout.text(for: provider?.trapSnapshot ?? .unavailable)
    }

    // MARK: - Actions

    private func applySelection() {
        let index = trapControl.indexOfSelectedItem
        provider?.selectTrap(trapKeys.indices.contains(index) ? trapKeys[index] : nil)
    }

    @objc private func selectTrap() {
        applySelection()
        finishInteraction()
    }

    @objc private func fire() {
        applySelection()
        provider?.fireSelectedTrap()
        finishInteraction()
    }

    @objc private func disarm() {
        applySelection()
        provider?.disarmSelectedTrap()
        finishInteraction()
    }
}
