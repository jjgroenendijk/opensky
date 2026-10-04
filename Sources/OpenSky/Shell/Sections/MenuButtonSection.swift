// A section of push buttons that each send one action to a menu coordinator,
// over a text readout. The menu sections of World > Map and World > Character
// share it, so each only lists its buttons and its readout.

import AppKit

class MenuButtonSection: PanelSectionViewController {
    struct Action {
        let title: String
        let identifier: String
        let toolTip: String
        let run: () -> Void
    }

    private var actions: [Action] = []
    private(set) var buttons: [NSButton] = []
    let statsLabel: NSTextField

    init(statsIdentifier: String) {
        statsLabel = PanelComponents.statsLabel(identifier: statsIdentifier)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// Rows of actions, top to bottom.
    func makeActions() -> [[Action]] {
        []
    }

    func readoutText() -> String {
        ""
    }

    func isEnabled(_ identifier: String) -> Bool {
        true
    }

    override func makeContentViews() -> [NSView] {
        let rows = makeActions()
        actions = rows.flatMap(\.self)
        var views: [NSView] = rows.map { row in
            PanelComponents.buttonRow(row.map(makeButton))
        }
        views.append(statsLabel)
        return [PanelComponents.group(views)]
    }

    private func makeButton(_ action: Action) -> NSButton {
        let button = NSButton(title: action.title, target: nil, action: nil)
        button.tag = buttons.count
        button.toolTip = action.toolTip
        PanelComponents.configureButton(
            button, target: self, action: #selector(pressed(_:)), identifier: action.identifier
        )
        buttons.append(button)
        return button
    }

    override func refreshReadout() {
        statsLabel.stringValue = readoutText()
        for button in buttons {
            button.isEnabled = isEnabled(actions[button.tag].identifier)
        }
    }

    @objc private func pressed(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag].run()
        finishInteraction()
    }

    /// One line per row, the selected one marked.
    nonisolated static func list(_ rows: [String], selected: Int) -> String {
        rows.enumerated().map { index, row in
            (index == selected ? "> " : "  ") + row
        }.joined(separator: "\n")
    }
}
