// `FakeWorldProviders`' JournalControlProviding forwarding (issue #184). The fake
// is shared by both test targets, so every conformance it carries has to be too;
// the suite that used to hold this lives on in openskyTests. See
// openskyTestSupport/AGENTS.md.

import AppKit
@testable import opensky
import Testing

/// Forwards the journal seam to the panel tests' recorder rather than
/// duplicating it, so a registry-level reset and a panel-level button click are
/// observed through the same fake.
extension FakeWorldProviders {
    var journalSnapshot: JournalControlSnapshot {
        journal.journalSnapshot
    }

    var journalQuestEditorID: String {
        get { journal.journalQuestEditorID }
        set { journal.journalQuestEditorID = newValue }
    }

    var journalQuestEditorIDs: [String] {
        journal.journalQuestEditorIDs
    }

    func openJournal() {
        journal.openJournal()
    }

    func closeJournal() {
        journal.closeJournal()
    }

    func sendJournalInput(_ event: MenuInputEvent) {
        journal.sendJournalInput(event)
    }

    func setJournalShowsCompleted(_ flag: Bool) {
        journal.setJournalShowsCompleted(flag)
    }

    func startSelectedQuest() {
        journal.startSelectedQuest()
    }

    func stopSelectedQuest() {
        journal.stopSelectedQuest()
    }

    func setSelectedQuestStage(_ index: Int) {
        journal.setSelectedQuestStage(index)
    }

    func setSelectedQuestObjective(_ index: Int, displayed: Bool) {
        journal.setSelectedQuestObjective(index, displayed: displayed)
    }

    func journalAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        journal.journalAliasTable(editorID: editorID)
    }
}
