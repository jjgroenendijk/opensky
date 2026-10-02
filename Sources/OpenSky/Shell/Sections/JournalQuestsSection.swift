// World > Quests & Journal > Quests: quest state, and the quest the other
// sections act on. The picker shares its combo-box with the Scripts panel, so
// a quest has the same name on both.

import AppKit
import OpenSkyMenus
import OpenSkyScripting
import OpenSkyScriptingInterface

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
        questControl.toolTip = "Quests the journal lists, with stage and objectives."
        aliasLabel.toolTip = "Aliases fill when the quest starts and clear when it stops."
        PanelComponents.configureComboBox(
            questControl, target: self, action: #selector(questSelected),
            identifier: "JournalQuestControl", width: 220
        )
        return [
            statsLabel,
            PanelComponents.group([
                questControl
            ]),
            selectionLabel,
            PanelComponents.separator(),
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
