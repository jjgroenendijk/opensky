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
import OpenSkyRendering
import OpenSkyScriptingInterface

/// One quest as the panel lists it — running state, current stage, and the
/// display state of each objective the record declares.
nonisolated public struct JournalQuestRow: Equatable, Sendable {
    public let editorID: String
    /// FULL, resolved, or the editor ID when the plugin's tables answer nothing.
    public let title: String
    /// `Quest.Kind.name`, so a row states which journal category it belongs to.
    public let kind: String
    public let isRunning: Bool
    public let isCompleted: Bool
    /// Highest stage reached, nil when the quest has reached none.
    public let stage: UInt16?
    /// Stages the quest declares, for the stage control's range.
    public let declaredStages: [UInt16]
    /// One entry per objective the record declares, worded as
    /// `"<index> <state>"`, where the state is `displayed`, `completed`,
    /// `failed` or `untouched`.
    public let objectives: [String]

    public init(
        editorID: String,
        title: String,
        kind: String,
        isRunning: Bool,
        isCompleted: Bool,
        stage: UInt16?,
        declaredStages: [UInt16],
        objectives: [String]
    ) {
        self.editorID = editorID
        self.title = title
        self.kind = kind
        self.isRunning = isRunning
        self.isCompleted = isCompleted
        self.stage = stage
        self.declaredStages = declaredStages
        self.objectives = objectives
    }
}

/// Everything the journal readouts show, captured in one value.
nonisolated public struct JournalControlSnapshot: Equatable, Sendable {
    /// Rows a snapshot carries. A real install runs a hundred-odd quests at
    /// once, and the panel shows the ones the user asked about plus the running
    /// set, not the whole index.
    public static let rowLimit = 12

    public static let empty = JournalControlSnapshot(
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
    public let hasQuestIndex: Bool
    /// Quests the plugin declares that the journal would ever list.
    public let questCount: Int
    public let runningCount: Int
    public let completedCount: Int
    /// The rows the panel shows, at most `rowLimit` of them.
    public let rows: [JournalQuestRow]
    public let droppedRowCount: Int
    /// Quest the dev controls act on, trimmed. Empty means none picked.
    public let selectedEditorID: String
    /// That quest's row, or nil when no loaded plugin defines it.
    public let selectedRow: JournalQuestRow?
    /// The journal text of that quest as the page would show it.
    public let selectedObjectives: [String]
    public let selectedLogEntries: [String]
    /// Result of the last dev control, worded for the readout. Nil until one
    /// runs.
    public let lastOutcome: String?

    // MARK: Journal presentation

    public let isOpen: Bool
    /// Menu-stack identifiers currently open, top last. Proves the journal
    /// drives the engine's own stack rather than a private flag.
    public let openMenus: [String]
    public let showsCompleted: Bool
    /// Rows the page is listing — the active or the completed list.
    public let listedQuestCount: Int
    /// Row the page has selected, or -1 for none.
    public let selectedIndex: Int

    public let movieLoaded: Bool
    public let movieError: String?
    /// Rows the movie's own `QuestTitleList` holds, read back out of it.
    public let movieQuestRows: Int
    public let movieObjectiveRows: Int
    /// Text the page's own title field holds.
    public let movieTitleText: String?
    /// Frame label of each visible objective entry clip.
    public let movieObjectiveFrames: [String]
    public let movieFaults: Int
    public let movieMissingNames: Int
    public let movieUnhandledInvokes: Int
    public let movieDrawStats: SWFDrawStats

    public init(
        hasQuestIndex: Bool,
        questCount: Int,
        runningCount: Int,
        completedCount: Int,
        rows: [JournalQuestRow],
        droppedRowCount: Int,
        selectedEditorID: String,
        selectedRow: JournalQuestRow?,
        selectedObjectives: [String],
        selectedLogEntries: [String],
        lastOutcome: String?,
        isOpen: Bool,
        openMenus: [String],
        showsCompleted: Bool,
        listedQuestCount: Int,
        selectedIndex: Int,
        movieLoaded: Bool,
        movieError: String?,
        movieQuestRows: Int,
        movieObjectiveRows: Int,
        movieTitleText: String?,
        movieObjectiveFrames: [String],
        movieFaults: Int,
        movieMissingNames: Int,
        movieUnhandledInvokes: Int,
        movieDrawStats: SWFDrawStats
    ) {
        self.hasQuestIndex = hasQuestIndex
        self.questCount = questCount
        self.runningCount = runningCount
        self.completedCount = completedCount
        self.rows = rows
        self.droppedRowCount = droppedRowCount
        self.selectedEditorID = selectedEditorID
        self.selectedRow = selectedRow
        self.selectedObjectives = selectedObjectives
        self.selectedLogEntries = selectedLogEntries
        self.lastOutcome = lastOutcome
        self.isOpen = isOpen
        self.openMenus = openMenus
        self.showsCompleted = showsCompleted
        self.listedQuestCount = listedQuestCount
        self.selectedIndex = selectedIndex
        self.movieLoaded = movieLoaded
        self.movieError = movieError
        self.movieQuestRows = movieQuestRows
        self.movieObjectiveRows = movieObjectiveRows
        self.movieTitleText = movieTitleText
        self.movieObjectiveFrames = movieObjectiveFrames
        self.movieFaults = movieFaults
        self.movieMissingNames = movieMissingNames
        self.movieUnhandledInvokes = movieUnhandledInvokes
        self.movieDrawStats = movieDrawStats
    }
}

/// Live-renderer seam for the World > Quests & Journal panel.
///
/// `refocusGameView()` is deliberately absent: `HUDControlProviding` already
/// declares it and the panel reaches it through the composed
/// `WorldControlProviders`.
@MainActor
public protocol JournalControlProviding: AnyObject {
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
