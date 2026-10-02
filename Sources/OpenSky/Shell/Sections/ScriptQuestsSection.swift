// World > Scripts > Quests: whether quests reached the VM and whether their
// stage fragments ran. Quest stage state belongs to the journal destination.
// A readout only.

import AppKit
import OpenSkyScripting
import OpenSkyScriptingInterface

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
        questAliasControl.toolTip = "Aliases fill when the quest starts and clear when it stops."
        PanelComponents.configureComboBox(
            questAliasControl, target: self, action: #selector(questSelected),
            identifier: "ScriptQuestAliasControl", width: 220
        )
        return [
            statsLabel,
            PanelComponents.group([
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
