// Engine-side model of the journal's Quests page (issue #184, roadmap item
// 13.5): what the player would see listed, independent of any movie.
//
// The same split every other menu in `opensky/UI/` uses. `JournalMenuModel` is
// a `nonisolated struct` holding rows, selection and the completed-quests
// toggle; `QuestJournalMovieBridge` is what pushes those rows through the
// measured `quest_journal.swf` contract. Keeping the two apart is what lets the
// panel and the CLI probe assert the same rows with no window, no renderer and
// no install.
//
// Nothing here is derived from memory of Skyrim's journal. The row set is the
// quest state issue #182 records, the text is what `LocalizedStrings` resolves
// out of the plugin's own tables, and the objective display flags are the three
// independent booleans `QuestObjectiveState` already models.
//
// Documented in docs/engine/journal.md.

import Foundation

/// One objective line under a quest.
nonisolated struct JournalObjectiveEntry: Equatable, Sendable {
    /// How the journal draws this line. The three source flags are
    /// independent, so a precedence is needed: a failed objective reads as
    /// failed whatever else is set, then completed, then plain displayed.
    /// That order is the Creation Kit's own — `SetObjectiveFailed` is
    /// documented as the terminal state of an objective
    /// (<https://ck.uesp.net/wiki/SetObjectiveFailed_-_Quest>).
    enum State: Equatable, Sendable {
        case displayed
        case completed
        case failed
    }

    /// QOBJ index, which is also what a script addresses the objective by.
    let index: UInt16
    /// NNAM, resolved. Never empty: an objective whose text does not resolve
    /// falls back to its own index so the row still names something.
    let text: String
    let state: State
}

/// One quest row, with everything the page shows once it is selected.
nonisolated struct JournalQuestEntry: Equatable, Sendable {
    let formID: FormID
    /// Editor ID, or the FormID's hex spelling when the record carries none.
    let editorID: String
    /// FULL, resolved. Falls back to the editor ID, because a row with no
    /// label is unselectable.
    let title: String
    let kind: Quest.Kind
    let isCompleted: Bool
    /// Highest stage reached, nil when the quest has reached none.
    let stage: UInt16?
    /// Displayed objectives only. A quest whose objectives are all untouched
    /// shows none, which is what the vanilla page does.
    let objectives: [JournalObjectiveEntry]
    /// CNAM text of every reached stage, oldest first — the journal's running
    /// account of the quest.
    let logEntries: [String]

    /// The journal's description block: the log entries as one paragraph run,
    /// newest last, which is the order the reached stages come in.
    var descriptionText: String {
        logEntries.joined(separator: "\n\n")
    }
}

/// Rows, selection and the completed-quests toggle of the Quests page.
nonisolated struct JournalMenuModel: Equatable {
    /// Running quests, in editor-ID order.
    let active: [JournalQuestEntry]
    /// Quests flagged completed, in the same order. A quest can be in both:
    /// `CompleteQuest()` does not stop a quest (`QuestRuntimeState.completing`).
    let completed: [JournalQuestEntry]
    /// Which of the two lists the page is showing.
    private(set) var showsCompleted: Bool
    /// Row index into `entries`, or -1 when the shown list is empty. -1 is the
    /// movie's own nothing-selected sentinel, measured on `iSelectedIndex`.
    private(set) var selectedIndex: Int

    static let empty = JournalMenuModel(active: [], completed: [])

    init(
        active: [JournalQuestEntry],
        completed: [JournalQuestEntry],
        showsCompleted: Bool = false,
        selectedIndex: Int = 0
    ) {
        self.active = active
        self.completed = completed
        self.showsCompleted = showsCompleted
        let shown = showsCompleted ? completed : active
        self.selectedIndex = shown.isEmpty ? -1 : min(max(selectedIndex, 0), shown.count - 1)
    }

    /// The rows currently on the page.
    var entries: [JournalQuestEntry] {
        showsCompleted ? completed : active
    }

    var selectedEntry: JournalQuestEntry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    /// True when the page has nothing to list, which is the one case the movie
    /// answers with its own `NoQuestsText` rather than with a list.
    var isEmpty: Bool {
        entries.isEmpty
    }

    /// Points the page at one row, clamped. An empty list stays at -1.
    mutating func select(_ index: Int) {
        selectedIndex = entries.isEmpty ? -1 : min(max(index, 0), entries.count - 1)
    }

    /// Moves the selection by `delta` rows without wrapping, matching the
    /// vanilla title list, whose `moveSelectionUp`/`moveSelectionDown` stop at
    /// the ends rather than wrapping.
    mutating func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        select(selectedIndex + delta)
    }

    /// Switches between the active and completed lists, re-clamping the
    /// selection into whichever list is now shown.
    mutating func setShowsCompleted(_ flag: Bool) {
        guard flag != showsCompleted else { return }
        showsCompleted = flag
        select(0)
    }
}
