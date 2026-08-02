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

    private let statsLabel = PanelComponents.statsLabel(identifier: "ScriptQuestsStatsLabel")

    override var sectionTitle: String {
        "Quests"
    }

    override var sectionIdentifier: String {
        "scriptQuests"
    }

    /// Current readout text; the verification-surface tests read it directly.
    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        [
            PanelComponents.note(
                "Quest scripts are instantiated for every running quest and never attach or "
                    + "detach with a cell. Setting a stage queues that stage's fragment on the "
                    + "same event queue every other script event uses."
            ),
            statsLabel
        ]
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Papyrus: unavailable"
            return
        }
        statsLabel.stringValue = ScriptsReadout.questsText(for: provider.scriptsSnapshot)
    }
}
