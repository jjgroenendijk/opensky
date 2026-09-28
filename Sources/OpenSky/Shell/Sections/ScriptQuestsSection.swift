// World > Scripts > Quests section (issue #322): whether the session's quests
// actually reached the VM, and whether their stage fragments ran.
//
// It sits under Scripts rather than under Runtime State because everything it
// counts is a script fact — instances and dispatched fragments. Quest *state*
// (which quest is on which stage) is the journal's surface, issue #184.
//
// Purely a readout, like the Instances section: nothing here is a setting, so
// it is never overridden and its reset is a no-op.

import AppKit

final class ScriptQuestsSection: PanelSectionViewController {
    weak var provider: (any ScriptControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let questAliasControl = NSComboBox()

    private let statsLabel = PanelComponents.statsLabel(identifier: "ScriptQuestsStatsLabel")
    private let aliasLabel = PanelComponents.statsLabel(
        identifier: "ScriptQuestAliasStatsLabel"
    )
    /// Completion list the combo box currently holds, so the 2 Hz sync only
    /// rebuilds it when the loaded plugins actually changed it.
    private var loadedEditorIDs: [String] = []

    override var sectionTitle: String {
        "Quests"
    }

    override var sectionIdentifier: String {
        "scriptQuests"
    }

    /// Current readout texts; the verification-surface tests read them directly.
    var readout: String {
        statsLabel.stringValue
    }

    var aliasReadout: String {
        aliasLabel.stringValue
    }

    /// Quest the alias inspector is pointed at, trimmed. Empty means none,
    /// which the readout states rather than guessing at a quest.
    var aliasEditorID: String {
        questAliasControl.stringValue.trimmingCharacters(in: .whitespaces)
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureComboBox(
            questAliasControl, target: self, action: #selector(questSelected),
            identifier: "ScriptQuestAliasControl", width: 220
        )
        return [
            PanelComponents.note(
                "Quest scripts are instantiated for every running quest and never attach or "
                    + "detach with a cell. Setting a stage queues that stage's fragment on the "
                    + "same event queue every other script event uses."
            ),
            statsLabel,
            PanelComponents.group([
                PanelComponents.note(
                    "Aliases fill when a quest starts and clear when it stops. Pick a quest "
                        + "to see every alias it declares, how it is meant to fill, and what "
                        + "the session put in it."
                ),
                questAliasControl
            ]),
            aliasLabel
        ]
    }

    // MARK: Actions

    @objc private func questSelected() {
        finishInteraction()
    }

    // MARK: Sync and readout

    override func syncControls() {
        let available = provider?.questAliasQuestEditorIDs ?? []
        guard available != loadedEditorIDs else { return }
        loadedEditorIDs = available
        questAliasControl.removeAllItems()
        questAliasControl.addItems(withObjectValues: available)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Papyrus: unavailable"
            aliasLabel.stringValue = ""
            return
        }
        statsLabel.stringValue = ScriptsReadout.questsText(for: provider.scriptsSnapshot)
        let editorID = aliasEditorID
        aliasLabel.stringValue = ScriptsReadout.questAliasText(
            for: editorID.isEmpty ? nil : provider.questAliasTable(editorID: editorID),
            editorID: editorID
        )
    }
}
