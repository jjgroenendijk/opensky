// Main-app journal seam (issue #184). Keeps the `World > Quests & Journal`
// panel independent of `GameViewController` while exposing quest state, the
// journal's menu-stack presence, and what the vanilla `quest_journal.swf`
// Quests page actually built.
//
// The seam mirrors `ScriptControlProviding`: the panel reads one snapshot per
// refresh and calls one mutation entry point per user action. It never sees
// `QuestRuntime`, `MenuStack` or `SWFMovieRuntime` directly, so the engine keeps
// ownership of main-actor state.
//
// The alias-provenance readout deliberately reuses `ScriptQuestAliasInspection`
// and `ScriptsReadout.questAliasText` rather than restating the alias table in a
// second shape: the two panels show the same #183 fill table, and two spellings
// of it could disagree.
//
// Documented in docs/engine/journal.md.

import Foundation

/// One quest as the panel lists it — running state, current stage, and the
/// display state of each objective the record declares.
nonisolated struct JournalQuestRow: Equatable, Sendable {
    let editorID: String
    /// FULL, resolved, or the editor ID when the plugin's tables answer nothing.
    let title: String
    /// `Quest.Kind.name`, so a row states which journal category it belongs to.
    let kind: String
    let isRunning: Bool
    let isCompleted: Bool
    /// Highest stage reached, nil when the quest has reached none.
    let stage: UInt16?
    /// Stages the quest declares, for the stage control's range.
    let declaredStages: [UInt16]
    /// One entry per objective the record declares, worded as
    /// `"<index> <state>"`, where the state is `displayed`, `completed`,
    /// `failed` or `untouched`.
    let objectives: [String]
}

/// Everything the journal readouts show, captured in one value.
nonisolated struct JournalControlSnapshot: Equatable {
    /// Rows a snapshot carries. A real install runs a hundred-odd quests at
    /// once, and the panel shows the ones the user asked about plus the running
    /// set, not the whole index.
    static let rowLimit = 12

    static let empty = JournalControlSnapshot(
        hasQuestIndex: false,
        questCount: 0,
        runningCount: 0,
        completedCount: 0,
        rows: [],
        droppedRowCount: 0,
        selectedEditorID: "",
        selectedRow: nil,
        selectedObjectives: [],
        selectedLogEntries: [],
        lastOutcome: nil,
        isOpen: false,
        openMenus: [],
        showsCompleted: false,
        listedQuestCount: 0,
        selectedIndex: -1,
        movieLoaded: false,
        movieError: nil,
        movieQuestRows: 0,
        movieObjectiveRows: 0,
        movieTitleText: nil,
        movieObjectiveFrames: [],
        movieFaults: 0,
        movieMissingNames: 0,
        movieUnhandledInvokes: 0,
        movieDrawStats: SWFDrawStats()
    )

    // MARK: Quest state

    /// False when the session loaded no plugin, which is the one case the
    /// readout states rather than showing zeros that look like an empty index.
    let hasQuestIndex: Bool
    /// Quests the plugin declares that the journal would ever list.
    let questCount: Int
    let runningCount: Int
    let completedCount: Int
    /// The rows the panel shows, at most `rowLimit` of them.
    let rows: [JournalQuestRow]
    let droppedRowCount: Int
    /// Quest the dev controls act on, trimmed. Empty means none picked.
    let selectedEditorID: String
    /// That quest's row, or nil when no loaded plugin defines it.
    let selectedRow: JournalQuestRow?
    /// The journal text of that quest as the page would show it.
    let selectedObjectives: [String]
    let selectedLogEntries: [String]
    /// Result of the last dev control, worded for the readout. Nil until one
    /// runs.
    let lastOutcome: String?

    // MARK: Journal presentation

    let isOpen: Bool
    /// Menu-stack identifiers currently open, top last. Proves the journal
    /// drives the engine's own stack rather than a private flag.
    let openMenus: [String]
    let showsCompleted: Bool
    /// Rows the page is listing — the active or the completed list.
    let listedQuestCount: Int
    /// Row the page has selected, or -1 for none.
    let selectedIndex: Int

    let movieLoaded: Bool
    let movieError: String?
    /// Rows the movie's own `QuestTitleList` holds, read back out of it.
    let movieQuestRows: Int
    let movieObjectiveRows: Int
    /// Text the page's own title field holds.
    let movieTitleText: String?
    /// Frame label of each visible objective entry clip.
    let movieObjectiveFrames: [String]
    let movieFaults: Int
    let movieMissingNames: Int
    let movieUnhandledInvokes: Int
    let movieDrawStats: SWFDrawStats
}

/// Live-renderer seam for the World > Quests & Journal panel.
///
/// `refocusGameView()` is deliberately absent: `HUDControlProviding` already
/// declares it and the panel reaches it through the composed
/// `WorldControlProviders`.
@MainActor
protocol JournalControlProviding: AnyObject {
    /// One sample of everything the readouts show.
    /// `JournalControlSnapshot.empty` when the session has no quest index.
    var journalSnapshot: JournalControlSnapshot { get }

    /// Quest the dev controls and the alias readout act on. Setting it to a
    /// quest the plugin does not define leaves the readouts saying so rather
    /// than failing.
    var journalQuestEditorID: String { get set }

    /// Editor IDs of every quest the journal would list, sorted. Empty when the
    /// session has no quest index.
    var journalQuestEditorIDs: [String] { get }

    /// Opens the journal on its Quests page, pushing the engine menu stack.
    /// No-op when it is already open.
    func openJournal()

    /// Closes it and pops the stack. No-op when it is not open.
    func closeJournal()

    /// Routes one menu event through the same path as the live keys, so the
    /// panel buttons and the keyboard cannot diverge.
    func sendJournalInput(_ event: MenuInputEvent)

    /// Switches the page between the active and completed quest lists.
    func setJournalShowsCompleted(_ flag: Bool)

    /// Starts the selected quest, filling its aliases (issue #183). Records the
    /// outcome, including a refused start, in `lastOutcome`.
    func startSelectedQuest()

    /// Stops the selected quest, clearing its alias table.
    func stopSelectedQuest()

    /// Sets one stage on the selected quest.
    func setSelectedQuestStage(_ index: Int)

    /// Shows or hides one objective of the selected quest, which is what puts a
    /// line on the page without a script.
    func setSelectedQuestObjective(_ index: Int, displayed: Bool)

    /// The selected quest's #183 alias table, or nil when no loaded plugin
    /// defines a quest with that editor ID.
    func journalAliasTable(editorID: String) -> ScriptQuestAliasInspection?
}
