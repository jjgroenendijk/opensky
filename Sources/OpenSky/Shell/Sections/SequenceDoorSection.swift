// World > World > Animated Doors: the loaded doors that open with their mesh's
// `Open` and `Close` sequences, their state, and an open or close as `SetOpen` does.

import AppKit
import OpenSkyObjectAnimation

final class SequenceDoorSection: PanelSectionViewController {
    weak var provider: (any SequenceDoorControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let doorControl = NSPopUpButton()
    let openControl = NSButton(title: "Open", target: nil, action: nil)
    let closeControl = NSButton(title: "Close", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "SequenceDoorStatsLabel")
    private var references: [UInt32] = []
    private var lastText = "Last: none"

    override var sectionTitle: String {
        "Animated Doors"
    }

    override var sectionIdentifier: String {
        "sequenceDoors"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            doorControl, target: self, action: #selector(selectDoor),
            identifier: "SequenceDoorDoorControl", width: 260
        )
        openControl.toolTip = "Opens the door, as a script's SetOpen does."
        PanelComponents.configureButton(
            openControl, target: self, action: #selector(open),
            identifier: "SequenceDoorOpenControl"
        )
        closeControl.toolTip = "Closes the door, as a script's SetOpen(false) does."
        PanelComponents.configureButton(
            closeControl, target: self, action: #selector(close),
            identifier: "SequenceDoorCloseControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Door", captionWidth: 60, field: doorControl
                ),
                PanelComponents.buttonRow([openControl, closeControl])
            ]),
            statsLabel
        ]
    }

    var readout: String {
        statsLabel.stringValue
    }

    private var selected: UInt32? {
        let index = doorControl.indexOfSelectedItem
        return references.indices.contains(index) ? references[index] : nil
    }

    override func syncControls() {
        let rows = provider?.sequenceDoorRows ?? []
        let keys = rows.map(\.reference)
        if keys != references {
            let previous = selected
            references = keys
            doorControl.removeAllItems()
            doorControl.addItems(withTitles: rows.map(SequenceDoorReadout.title))
            if let previous, let index = keys.firstIndex(of: previous) {
                doorControl.selectItem(at: index)
            }
        }
        doorControl.isEnabled = !references.isEmpty
        openControl.isEnabled = selected != nil
        closeControl.isEnabled = selected != nil
    }

    override func refreshReadout() {
        syncControls()
        statsLabel.stringValue = SequenceDoorReadout.text(
            rows: provider?.sequenceDoorRows ?? [], selected: selected, last: lastText
        )
    }

    @objc private func selectDoor() {
        refreshReadout()
        finishInteraction()
    }

    @objc private func open() {
        setOpen(true)
    }

    @objc private func close() {
        setOpen(false)
    }

    private func setOpen(_ open: Bool) {
        guard let reference = selected else { return }
        let done = provider?.setSequenceDoorOpen(open, reference: reference) ?? false
        let verb = open ? "Opened" : "Closed"
        lastText = done ? "Last: \(verb) \(String(format: "%08X", reference))" : "Last: not loaded"
        refreshReadout()
        finishInteraction()
    }
}
