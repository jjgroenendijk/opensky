// World > Quests & Journal > Quests section (issue #184): what the session's
// quests are doing, and which one the rest of the destination acts on.
//
// The list half is a readout — running state, current stage and per-objective
// display state — so nothing here is a setting and its reset is a no-op. The
// quest picker is not a setting either: it selects what to inspect, exactly as
// the Scripts panel's alias picker does, and the two share the same combo-box
// component so a quest is named the same way on both surfaces.

import AppKit

final class JournalQuestsSection: PanelSectionViewController {
    weak var provider: (any JournalControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let questControl = NSComboBox()

    private let statsLabel = PanelComponents.statsLabel(identifier: "JournalQuestsStatsLabel")
    private let selectionLabel = PanelComponents.statsLabel(
        identifier: "JournalSelectionStatsLabel"
    )
    private let aliasLabel = PanelComponents.statsLabel(
        identifier: "JournalAliasStatsLabel"
    )
    /// Completion list the combo box currently holds, so the 2 Hz sync only
    /// rebuilds it when the loaded plugins actually changed it.
    private var loadedEditorIDs: [String] = []

    override var sectionTitle: String {
        "Quests"
    }

    override var sectionIdentifier: String {
        "journalQuests"
    }

    /// Current readout texts; the verification-surface tests read them directly.
    var readout: String {
        statsLabel.stringValue
    }

    var selectionReadout: String {
        selectionLabel.stringValue
    }

    var aliasReadout: String {
        aliasLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureComboBox(
            questControl, target: self, action: #selector(questSelected),
            identifier: "JournalQuestControl", width: 220
        )
        return [
            PanelComponents.note(
                "Every quest the journal would list, with the highest stage it has reached "
                    + "and the display state of each objective it declares. A quest whose "
                    + "type keeps it out of the journal is not listed at all."
            ),
            statsLabel,
            PanelComponents.group([
                PanelComponents.note(
                    "Pick a quest to see it as the page would show it, drive it with the "
                        + "controls below, and read the alias table it filled when it started."
                ),
                questControl
            ]),
            selectionLabel,
            PanelComponents.separator(),
            PanelComponents.note(
                "Aliases fill when a quest starts and clear when it stops. This is the same "
                    + "table World > Scripts > Quests shows, for the quest selected here."
            ),
            aliasLabel
        ]
    }

    // MARK: Actions

    @objc private func questSelected() {
        provider?.journalQuestEditorID = questControl.stringValue
            .trimmingCharacters(in: .whitespaces)
        refreshReadout()
        finishInteraction()
    }

    // MARK: Sync and readout

    override func syncControls() {
        let available = provider?.journalQuestEditorIDs ?? []
        guard available != loadedEditorIDs else { return }
        loadedEditorIDs = available
        questControl.removeAllItems()
        questControl.addItems(withObjectValues: available)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Quests: unavailable"
            selectionLabel.stringValue = ""
            aliasLabel.stringValue = ""
            return
        }
        let snapshot = provider.journalSnapshot
        statsLabel.stringValue = JournalReadout.questsText(for: snapshot)
        selectionLabel.stringValue = JournalReadout.selectionText(for: snapshot)
        let editorID = snapshot.selectedEditorID
        aliasLabel.stringValue = ScriptsReadout.questAliasText(
            for: editorID.isEmpty ? nil : provider.journalAliasTable(editorID: editorID),
            editorID: editorID
        )
    }
}
