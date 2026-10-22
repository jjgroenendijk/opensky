// World > Progression > Perk Choices: the Activate perk choices the crosshair target
// offers, and running one without the use key.

import AppKit
import OpenSkyMenus

final class PerkActivationSection: PanelSectionViewController {
    weak var provider: (any PerkActivationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    let choiceControl = NSPopUpButton()
    let runControl = NSButton(title: "Run", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "PerkChoiceStatsLabel")
    private var titles: [String] = []

    override var sectionTitle: String {
        "Perk Choices"
    }

    override var sectionIdentifier: String {
        "perkChoices"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        choiceControl.toolTip = "The perk choices the target under the crosshair offers."
        PanelComponents.configurePopUp(
            choiceControl, target: self, action: #selector(selectChoice),
            identifier: "PerkChoiceSelectControl", width: 260
        )
        runControl.toolTip = "Runs the selected choice on the target, as the use key would."
        PanelComponents.configureButton(
            runControl, target: self, action: #selector(runChoice),
            identifier: "PerkChoiceRunControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Choice",
                    captionWidth: 60,
                    field: choiceControl
                ),
                PanelComponents.buttonRow([runControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        apply(snapshot)
    }

    override func refreshReadout() {
        let snapshot = snapshot
        apply(snapshot)
        statsLabel.stringValue = snapshot.readout
    }

    private var snapshot: PerkActivationSnapshot {
        provider?.perkActivationSnapshot
            ?? PerkActivationSnapshot(target: nil, rows: [], lastRun: nil)
    }

    private func apply(_ snapshot: PerkActivationSnapshot) {
        let rows = snapshot.rows.map(\.title)
        if rows != titles {
            let selected = choiceControl.indexOfSelectedItem
            titles = rows
            choiceControl.removeAllItems()
            choiceControl.addItems(withTitles: rows)
            if rows.indices.contains(selected) {
                choiceControl.selectItem(at: selected)
            }
        }
        choiceControl.isEnabled = !rows.isEmpty
        runControl.isEnabled = !rows.isEmpty
    }

    @objc private func selectChoice() {
        finishInteraction()
    }

    @objc private func runChoice() {
        provider?.runPerkChoice(at: choiceControl.indexOfSelectedItem)
        finishInteraction()
    }
}
