// World > System Menu > Page: the open sub-page (Settings, Save, Load, Controls,
// Quit) with the keys a page reads, and Delete for a selected save.

import AppKit
import OpenSkyMenus

final class SystemMenuPageSection: MenuButtonSection {
    weak var provider: (any SystemMenuControlProviding)?

    init() {
        super.init(statsIdentifier: "SystemMenuPageStatsLabel")
    }

    override var sectionTitle: String {
        "Page"
    }

    override var sectionIdentifier: String {
        "systemMenuPage"
    }

    override func makeActions() -> [[Action]] {
        [
            [
                key("Left", "SystemMenuPageLeftControl", "Lower the selected value.", .move(.left)),
                key(
                    "Right",
                    "SystemMenuPageRightControl",
                    "Raise the selected value.",
                    .move(.right)
                ),
                key("Back", "SystemMenuPageBackControl", "Leave the page.", .button(.cancel))
            ],
            [
                Action(
                    title: "Delete Save", identifier: "SystemMenuDeleteSaveControl",
                    toolTip: "Ask to delete the selected save on the Load page."
                ) { [weak self] in self?.provider?.deleteSelectedSave() }
            ]
        ]
    }

    private func key(
        _ title: String,
        _ id: String,
        _ tip: String,
        _ event: MenuInputEvent
    ) -> Action {
        Action(title: title, identifier: id, toolTip: tip) { [weak self] in
            self?.provider?.sendSystemMenuInput(event)
        }
    }

    override func isEnabled(_ identifier: String) -> Bool {
        guard let page = provider?.systemMenuSnapshot.page.page else { return false }
        if identifier == "SystemMenuDeleteSaveControl" {
            return page == "load"
        }
        return page != "main"
    }

    override func readoutText() -> String {
        guard let snapshot = provider?.systemMenuSnapshot else { return "Page: unavailable" }
        return Self.readout(for: snapshot.page)
    }

    nonisolated static func readout(for page: SystemMenuPageSnapshot) -> String {
        var lines = ["Page: \(page.page)"]
        if !page.rows.isEmpty {
            lines.append(list(page.rows, selected: page.selectedIndex))
        }
        if let question = page.question {
            lines.append("Question: \(question)")
        }
        if let message = page.message {
            lines.append("Last result: \(message)")
        }
        return lines.joined(separator: "\n")
    }
}
