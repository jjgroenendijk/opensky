// Recording double and snapshot builder for the journal seam (issue #184),
// shared by the panel suite and by the destination-registry satellite.
//
// It lives in its own file for the same reason the Scripts fixture does:
// stored properties cannot live in an extension, so a fake shared across suites
// has to be one type in one file, and both parent suites sit near the repo
// file-length limit.

import AppKit
@testable import opensky

/// Builds a `JournalControlSnapshot` from only the fields a test cares about.
/// The snapshot is immutable by design and its memberwise initializer takes
/// twenty-odd arguments, so a test that wants one non-zero counter would
/// otherwise have to spell out the rest.
nonisolated func makeJournalSnapshot(
    hasQuestIndex: Bool = true,
    questCount: Int = 0,
    runningCount: Int = 0,
    completedCount: Int = 0,
    rows: [JournalQuestRow] = [],
    droppedRowCount: Int = 0,
    selectedEditorID: String = "",
    selectedRow: JournalQuestRow? = nil,
    selectedObjectives: [String] = [],
    selectedLogEntries: [String] = [],
    lastOutcome: String? = nil,
    isOpen: Bool = false,
    openMenus: [String] = [],
    showsCompleted: Bool = false,
    listedQuestCount: Int = 0,
    selectedIndex: Int = -1,
    movieLoaded: Bool = false,
    movieError: String? = nil,
    movieQuestRows: Int = 0,
    movieObjectiveRows: Int = 0,
    movieTitleText: String? = nil,
    movieObjectiveFrames: [String] = [],
    movieFaults: Int = 0,
    movieMissingNames: Int = 0,
    movieUnhandledInvokes: Int = 0,
    movieDrawStats: SWFDrawStats = SWFDrawStats()
) -> JournalControlSnapshot {
    JournalControlSnapshot(
        hasQuestIndex: hasQuestIndex,
        questCount: questCount,
        runningCount: runningCount,
        completedCount: completedCount,
        rows: rows,
        droppedRowCount: droppedRowCount,
        selectedEditorID: selectedEditorID,
        selectedRow: selectedRow,
        selectedObjectives: selectedObjectives,
        selectedLogEntries: selectedLogEntries,
        lastOutcome: lastOutcome,
        isOpen: isOpen,
        openMenus: openMenus,
        showsCompleted: showsCompleted,
        listedQuestCount: listedQuestCount,
        selectedIndex: selectedIndex,
        movieLoaded: movieLoaded,
        movieError: movieError,
        movieQuestRows: movieQuestRows,
        movieObjectiveRows: movieObjectiveRows,
        movieTitleText: movieTitleText,
        movieObjectiveFrames: movieObjectiveFrames,
        movieFaults: movieFaults,
        movieMissingNames: movieMissingNames,
        movieUnhandledInvokes: movieUnhandledInvokes,
        movieDrawStats: movieDrawStats
    )
}

nonisolated func makeJournalRow(
    editorID: String,
    title: String? = nil,
    kind: String = "main quest",
    isRunning: Bool = true,
    isCompleted: Bool = false,
    stage: UInt16? = nil,
    declaredStages: [UInt16] = [],
    objectives: [String] = []
) -> JournalQuestRow {
    JournalQuestRow(
        editorID: editorID,
        title: title ?? editorID,
        kind: kind,
        isRunning: isRunning,
        isCompleted: isCompleted,
        stage: stage,
        declaredStages: declaredStages,
        objectives: objectives
    )
}

/// Records every journal mutation the panel asks for, and mirrors the ones the
/// readouts show back into the next snapshot — an open journal above all, since
/// that is what lights the destination's override indicator.
@MainActor
final class FakeJournalProvider: JournalControlProviding {
    var journalSnapshot = makeJournalSnapshot()
    var journalQuestEditorIDs: [String] = []
    /// Alias tables the fake serves, keyed by editor ID.
    var aliasTables: [String: ScriptQuestAliasInspection] = [:]

    /// Every menu event the panel routed, in order.
    private(set) var inputEvents: [MenuInputEvent] = []
    /// Quest mutations the panel asked for, worded the way the panel's own
    /// readout would, so one assertion covers both the call and its argument.
    private(set) var mutations: [String] = []
    private(set) var openCount = 0
    private(set) var closeCount = 0

    var journalQuestEditorID: String {
        get { journalSnapshot.selectedEditorID }
        set { journalSnapshot = Self.withSelection(journalSnapshot, newValue) }
    }

    func openJournal() {
        openCount += 1
        journalSnapshot = Self.withOpen(journalSnapshot, true)
    }

    func closeJournal() {
        closeCount += 1
        journalSnapshot = Self.withOpen(journalSnapshot, false)
    }

    func sendJournalInput(_ event: MenuInputEvent) {
        inputEvents.append(event)
    }

    func setJournalShowsCompleted(_ flag: Bool) {
        mutations.append("showsCompleted \(flag)")
        journalSnapshot = Self.withCompleted(journalSnapshot, flag)
    }

    func startSelectedQuest() {
        mutations.append("start \(journalQuestEditorID)")
    }

    func stopSelectedQuest() {
        mutations.append("stop \(journalQuestEditorID)")
    }

    func setSelectedQuestStage(_ index: Int) {
        mutations.append("stage \(index)")
    }

    func setSelectedQuestObjective(_ index: Int, displayed: Bool) {
        mutations.append("objective \(index) \(displayed)")
    }

    func journalAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        aliasTables[editorID]
    }

    // MARK: - Snapshot rebuilds

    private static func withOpen(
        _ snapshot: JournalControlSnapshot, _ isOpen: Bool
    ) -> JournalControlSnapshot {
        rebuilt(snapshot, isOpen: isOpen)
    }

    private static func withCompleted(
        _ snapshot: JournalControlSnapshot, _ showsCompleted: Bool
    ) -> JournalControlSnapshot {
        rebuilt(snapshot, showsCompleted: showsCompleted)
    }

    private static func withSelection(
        _ snapshot: JournalControlSnapshot, _ editorID: String
    ) -> JournalControlSnapshot {
        rebuilt(snapshot, selectedEditorID: editorID)
    }

    /// One rebuild point so a new snapshot field cannot be dropped by three
    /// separate copies of the same mirror.
    private static func rebuilt(
        _ snapshot: JournalControlSnapshot,
        isOpen: Bool? = nil,
        showsCompleted: Bool? = nil,
        selectedEditorID: String? = nil
    ) -> JournalControlSnapshot {
        makeJournalSnapshot(
            hasQuestIndex: snapshot.hasQuestIndex,
            questCount: snapshot.questCount,
            runningCount: snapshot.runningCount,
            completedCount: snapshot.completedCount,
            rows: snapshot.rows,
            droppedRowCount: snapshot.droppedRowCount,
            selectedEditorID: selectedEditorID ?? snapshot.selectedEditorID,
            selectedRow: snapshot.selectedRow,
            selectedObjectives: snapshot.selectedObjectives,
            selectedLogEntries: snapshot.selectedLogEntries,
            lastOutcome: snapshot.lastOutcome,
            isOpen: isOpen ?? snapshot.isOpen,
            openMenus: snapshot.openMenus,
            showsCompleted: showsCompleted ?? snapshot.showsCompleted,
            listedQuestCount: snapshot.listedQuestCount,
            selectedIndex: snapshot.selectedIndex,
            movieLoaded: snapshot.movieLoaded,
            movieError: snapshot.movieError,
            movieQuestRows: snapshot.movieQuestRows,
            movieObjectiveRows: snapshot.movieObjectiveRows,
            movieTitleText: snapshot.movieTitleText,
            movieObjectiveFrames: snapshot.movieObjectiveFrames,
            movieFaults: snapshot.movieFaults,
            movieMissingNames: snapshot.movieMissingNames,
            movieUnhandledInvokes: snapshot.movieUnhandledInvokes,
            movieDrawStats: snapshot.movieDrawStats
        )
    }
}
