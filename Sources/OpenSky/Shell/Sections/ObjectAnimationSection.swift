// World > World > Animated Objects: the traps, doors, and levers a behaviour
// graph runs in the loaded cells, their current state, and a forced event.
// Beside Traps, because a trap script plays these graphs.

import AppKit
import OpenSkyWorld

final class ObjectAnimationSection: PanelSectionViewController {
    weak var provider: (any ObjectAnimationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Animate objects", target: nil, action: nil)
    let objectControl = NSPopUpButton()
    let eventControl = NSPopUpButton()
    let sendControl = NSButton(title: "Send event", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "ObjectAnimationStatsLabel")
    private var references: [UInt32] = []
    private var events: [String] = []
    private var lastText = "No event sent yet."

    override var sectionTitle: String {
        "Animated Objects"
    }

    override var sectionIdentifier: String {
        "objectAnimation"
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.toolTip = "Off holds every trap and door in its current pose."
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(toggleEnabled),
            identifier: "ObjectAnimationEnabledControl"
        )
        PanelComponents.configurePopUp(
            objectControl, target: self, action: #selector(selectObject),
            identifier: "ObjectAnimationObjectControl", width: 260
        )
        PanelComponents.configurePopUp(
            eventControl, target: self, action: #selector(selectEvent),
            identifier: "ObjectAnimationEventControl", width: 260
        )
        sendControl.toolTip = "Raises the event on the graph, as a script's PlayAnimation does."
        PanelComponents.configureButton(
            sendControl, target: self, action: #selector(send),
            identifier: "ObjectAnimationSendControl"
        )
        return [
            enabledControl,
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Object", captionWidth: 60, field: objectControl
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Event", captionWidth: 60, field: eventControl
                ),
                PanelComponents.buttonRow([sendControl])
            ]),
            statsLabel
        ]
    }

    private var selected: UInt32? {
        let index = objectControl.indexOfSelectedItem
        return references.indices.contains(index) ? references[index] : nil
    }

    override func syncControls() {
        let rows = provider?.objectAnimationRows ?? []
        enabledControl.state = provider?.objectAnimationEnabled ?? true ? .on : .off
        let keys = rows.map(\.reference)
        if keys != references {
            let previous = selected
            references = keys
            objectControl.removeAllItems()
            objectControl.addItems(withTitles: rows.map(ObjectAnimationReadout.title))
            if let previous, let index = keys.firstIndex(of: previous) {
                objectControl.selectItem(at: index)
            }
        }
        let rowEvents = rows.first { $0.reference == selected }?.events ?? []
        if rowEvents != events {
            events = rowEvents
            eventControl.removeAllItems()
            eventControl.addItems(withTitles: rowEvents)
        }
        objectControl.isEnabled = !references.isEmpty
        eventControl.isEnabled = !events.isEmpty
        sendControl.isEnabled = !events.isEmpty
    }

    override func refreshReadout() {
        syncControls()
        statsLabel.stringValue = ObjectAnimationReadout.text(
            rows: provider?.objectAnimationRows ?? [], selected: selected, last: lastText
        )
    }

    @objc private func toggleEnabled() {
        provider?.objectAnimationEnabled = enabledControl.state == .on
        refreshOverrideState()
        finishInteraction()
    }

    @objc private func selectObject() {
        refreshReadout()
        finishInteraction()
    }

    @objc private func selectEvent() {
        finishInteraction()
    }

    @objc private func send() {
        let index = eventControl.indexOfSelectedItem
        guard let reference = selected, events.indices.contains(index) else { return }
        let event = events[index]
        let sent = provider?.sendObjectAnimationEvent(event, to: reference) ?? false
        lastText = sent ? "Sent \(event)." : "\(event) was not accepted."
        refreshReadout()
        finishInteraction()
    }
}
