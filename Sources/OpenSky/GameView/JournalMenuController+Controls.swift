// The journal's controls: the snapshot the sections read, and the
// quest commands they send. `GameViewController` gets them through
// `JournalMenuHosting`, so it holds no journal logic.

import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering

extension JournalMenuController {
    /// One sample per refresh, so two sections never show a half-updated session.
    var snapshot: JournalControlSnapshot {
        guard let runtime = journal.runtime else { return .empty }
        let entries = journal.entries()
        let listed = JournalCore.listed(entries)
        let rows = listed.prefix(JournalControlSnapshot.rowLimit).map(Self.row)
        let selected = journal.selectedEditorID
        let selectedEntry = model.entries.first { $0.editorID == selected }
        return JournalControlSnapshot(
            hasQuestIndex: !runtime.quests.isEmpty,
            questCount: runtime.quests.journalQuests().count,
            runningCount: entries.count { $0.state.isRunning },
            completedCount: entries.count { $0.state.isCompleted },
            rows: Array(rows),
            droppedRowCount: max(listed.count - rows.count, 0),
            selectedEditorID: selected,
            selectedRow: journal.selectedEntry().map(Self.row),
            selectedObjectives: (selectedEntry?.objectives ?? []).map {
                "\($0.index) \($0.text)"
            },
            selectedLogEntries: selectedEntry?.logEntries ?? [],
            lastOutcome: journal.lastOutcome,
            isOpen: isOpen,
            openMenus: game.menuMode.stack.identifiers.map(\.name),
            showsCompleted: model.showsCompleted,
            listedQuestCount: model.entries.count,
            selectedIndex: model.selectedIndex,
            movieLoaded: movieLoaded,
            movieError: movieError,
            movieQuestRows: movieValue(QuestJournalMovieBridge.questLabels)?.count ?? 0,
            movieObjectiveRows: movieValue(QuestJournalMovieBridge.objectiveLabels)?.count ?? 0,
            movieTitleText: movieValue(QuestJournalMovieBridge.titleText).flatMap(\.self),
            movieObjectiveFrames: movieValue(QuestJournalMovieBridge.objectiveEntryFrames) ?? [],
            movieFaults: diagnostics?.faults ?? 0,
            movieMissingNames: diagnostics?.missingNames ?? 0,
            movieUnhandledInvokes: diagnostics?.unhandledInvokes ?? 0,
            movieDrawStats: movieLoaded
                ? (game.renderer?.lastSWFDrawStats ?? SWFDrawStats())
                : SWFDrawStats(),
            trackedQuests: journal.trackedEditorIDs,
            statLines: game.worldState.miscStats.values.sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }
        )
    }

    private func movieValue<Value>(_ read: (SWFMovieRuntime) -> Value) -> Value? {
        guard let runtime = movie.runtime else { return nil }
        return read(runtime)
    }

    private var diagnostics: QuestJournalDiagnostics? {
        movieValue(QuestJournalMovieBridge.diagnostics(runtime:))
    }
}

extension JournalMenuController {
    private static func row(_ entry: JournalQuestStatus) -> JournalQuestRow {
        JournalQuestRow(
            editorID: entry.quest.editorID ?? entry.quest.formID.description,
            title: JournalMenuModel.fallbackTitle(for: entry.quest),
            kind: entry.quest.kind.name,
            isRunning: entry.state.isRunning,
            isCompleted: entry.state.isCompleted,
            stage: entry.state.currentStage,
            declaredStages: JournalCore.declaredStages(of: entry.quest),
            objectives: JournalCore.objectiveLines(entry)
        )
    }
}
