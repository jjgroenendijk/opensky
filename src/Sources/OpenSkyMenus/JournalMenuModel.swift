// Engine-side model of the journal's Quests page (docs/engine/journal.md).
// `QuestJournalMovieBridge` pushes these rows into `quest_journal.swf`; the
// split lets readout and CLI check rows without a window or install.

import Foundation
public import OpenSkyFormatsESM

/// One objective line under a quest.
nonisolated public struct JournalObjectiveEntry: Equatable, Sendable {
    /// How the journal draws this line. The three source flags are
    /// independent, so a precedence is needed: a failed objective reads as
    /// failed whatever else is set, then completed, then plain displayed.
    /// That order is the Creation Kit's own — `SetObjectiveFailed` is
    /// documented as the terminal state of an objective
    /// (<https://ck.uesp.net/wiki/SetObjectiveFailed_-_Quest>).
    public enum State: Equatable, Sendable {
        case displayed
        case completed
        case failed
    }

    /// QOBJ index, which is also what a script addresses the objective by.
    public let index: UInt16
    /// NNAM, resolved. Never empty: an objective whose text does not resolve
    /// falls back to its own index so the row still names something.
    public let text: String
    public let state: State
    /// The quest the objective belongs to, which a misc row needs.
    public var quest = FormID(0)
    /// Its quest is tracked and the objective is open: the movie's `Active` frame.
    public var isActive = false
    /// The objective declares a `QSTA` target, so "Show on map" can find it.
    public var hasTargets = false
}

/// One quest row, with everything the page shows once it is selected.
nonisolated public struct JournalQuestEntry: Equatable, Sendable {
    public let formID: FormID
    /// Editor ID, or the FormID's hex spelling when the record carries none.
    public let editorID: String
    /// FULL, resolved. Falls back to the editor ID, because a row with no
    /// label is unselectable.
    public let title: String
    public let kind: Quest.Kind
    public let isCompleted: Bool
    /// Highest stage reached, nil when the quest has reached none.
    public let stage: UInt16?
    /// Displayed objectives only. A quest whose objectives are all untouched
    /// shows none, which is what the vanilla page does.
    public internal(set) var objectives: [JournalObjectiveEntry]
    /// CNAM text of the newest log entry, one paragraph per passing stage item. "Only
    /// the most recent log entry is displayed" (<https://ck.uesp.net/wiki/Quest_Stages_Tab>).
    public let logEntries: [String]
    public var isTracked = false
    /// A Fail Quest stage item failed it. It is listed with the finished quests.
    public var isFailed = false
    /// The running misc quests this one row stands for. Empty on a quest row.
    public var miscQuests: [FormID] = []

    public var isMiscGroup: Bool {
        !miscQuests.isEmpty
    }

    /// The journal's description block: the newest log entry's paragraphs.
    public var descriptionText: String {
        logEntries.joined(separator: "\n\n")
    }
}

/// Rows and selection of the Quests page.
nonisolated public struct JournalMenuModel: Equatable, Sendable {
    /// Running quests, in editor-ID order, with the misc group last.
    public let active: [JournalQuestEntry]
    /// Quests flagged completed or failed, in the same order. A quest can be in
    /// both: `CompleteQuest()` does not stop a quest (`QuestRuntimeState.completing`).
    public let completed: [JournalQuestEntry]
    /// The page's rows: the running quests, then the finished ones below them, the
    /// order the movie's own `completedQuestSort` gives. A finished quest that still
    /// runs is listed once, as finished.
    public let entries: [JournalQuestEntry]
    /// Row index into `entries`, or -1 when the list is empty. -1 is the
    /// movie's own nothing-selected sentinel, measured on `iSelectedIndex`.
    public private(set) var selectedIndex: Int

    public static let empty = JournalMenuModel(active: [], completed: [])

    public init(
        active: [JournalQuestEntry],
        completed: [JournalQuestEntry],
        selectedIndex: Int = 0
    ) {
        self.active = active
        self.completed = completed
        let finished = Set(completed.map(\.formID))
        entries = active.filter { !finished.contains($0.formID) || $0.isMiscGroup } + completed
        self.selectedIndex = entries.isEmpty ? -1 : min(max(selectedIndex, 0), entries.count - 1)
    }

    public var selectedEntry: JournalQuestEntry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    /// True when the page has nothing to list, which is the one case the movie
    /// answers with its own `NoQuestsText` rather than with a list.
    var isEmpty: Bool {
        entries.isEmpty
    }

    /// Points the page at one row, clamped. An empty list stays at -1.
    public mutating func select(_ index: Int) {
        selectedIndex = entries.isEmpty ? -1 : min(max(index, 0), entries.count - 1)
    }

    /// Moves the selection by `delta` rows without wrapping, matching the
    /// vanilla title list, whose `moveSelectionUp`/`moveSelectionDown` stop at
    /// the ends rather than wrapping.
    public mutating func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        select(selectedIndex + delta)
    }

    /// Points the page at the row of `quest`. The misc group carries FormID 0, as the
    /// movie's own misc row does.
    /// An unknown quest leaves the selection as it is.
    public mutating func select(quest: FormID) {
        if let row = entries.firstIndex(where: { $0.formID == quest }) {
            selectedIndex = row
        }
    }
}
