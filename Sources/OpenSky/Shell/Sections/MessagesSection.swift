// HUD & Interaction > Messages: show any message as a notification or a box,
// watch the notification queue, and reset the help-message counts.

import AppKit
import OpenSkyMenus

final class MessagesSection: PanelSectionViewController {
    weak var provider: (any MessageControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    let messageControl = NSComboBox()
    let notifyControl = NSButton(title: "Notify", target: nil, action: nil)
    let boxControl = NSButton(title: "Box", target: nil, action: nil)
    let resetHelpControl = NSButton(title: "Reset help", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "MessagesStatsLabel")
    private var messageNames: [String] = []

    override var sectionTitle: String {
        "Messages"
    }

    override var sectionIdentifier: String {
        "messages"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        messageControl.toolTip = "The message to show, by editor ID."
        PanelComponents.configureComboBox(
            messageControl, target: self, action: #selector(notify),
            identifier: "MessageSelectControl", width: 170
        )
        notifyControl.toolTip = "Shows the message text as a HUD notification."
        PanelComponents.configureButton(
            notifyControl, target: self, action: #selector(notify),
            identifier: "MessageNotifyControl"
        )
        boxControl.toolTip = "Opens the message as a box with its buttons."
        PanelComponents.configureButton(
            boxControl, target: self, action: #selector(openBox), identifier: "MessageBoxControl"
        )
        resetHelpControl.toolTip = "Lets every help message show again."
        PanelComponents.configureButton(
            resetHelpControl, target: self, action: #selector(resetHelp),
            identifier: "MessageResetHelpControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Message",
                    captionWidth: 60,
                    field: messageControl
                ),
                PanelComponents.buttonRow([notifyControl, boxControl, resetHelpControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        sync(provider?.messageSnapshot ?? MessageControlSnapshot())
    }

    private func sync(_ snapshot: MessageControlSnapshot) {
        if snapshot.messageNames != messageNames {
            messageNames = snapshot.messageNames
            messageControl.removeAllItems()
            messageControl.addItems(withObjectValues: messageNames)
        }
        for control in [messageControl, notifyControl, boxControl, resetHelpControl] {
            control.isEnabled = snapshot.isAvailable
        }
    }

    override func refreshReadout() {
        let snapshot = provider?.messageSnapshot ?? MessageControlSnapshot()
        sync(snapshot)
        statsLabel.stringValue = MessageReadout.text(for: snapshot)
    }

    private func show(asBox: Bool) {
        let name = messageControl.stringValue
        guard !name.isEmpty else { return }
        provider?.showMessage(editorID: name, asBox: asBox)
        finishInteraction()
    }

    @objc private func notify() {
        show(asBox: false)
    }

    @objc private func openBox() {
        show(asBox: true)
    }

    @objc private func resetHelp() {
        provider?.resetHelpMessages()
        finishInteraction()
    }
}
