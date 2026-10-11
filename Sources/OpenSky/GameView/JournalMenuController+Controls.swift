// The journal's sidebar controls: the snapshot the sections read, and the
// quest commands they send. `GameViewController` gets them through
// `JournalMenuHosting`, so it holds no journal logic.

import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState

/// A holder of the journal menu, which then provides the journal controls.
protocol JournalMenuHosting: AnyObject {
    var journalMenu: JournalMenuController { get }
}

extension JournalControlProviding where Self: JournalMenuHosting {
    var journalSnapshot: JournalControlSnapshot {
        journalMenu.snapshot
    }

    var journalQuestEditorID: String {
        get { journalMenu.journal.editorID }
        set { journalMenu.setEditorID(newValue) }
    }

    var journalQuestEditorIDs: [String] {
        journalMenu.journal.questEditorIDs
    }

    func openJournal() {
        journalMenu.open()
    }

    func closeJournal() {
        journalMenu.close()
    }

    func sendJournalInput(_ event: MenuInputEvent) {
        journalMenu.route(event)
    }

    func setJournalShowsCompleted(_ flag: Bool) {
        journalMenu.setShowsCompleted(flag)
    }

    func startSelectedQuest() {
        journalMenu.applied(journalMenu.journal.startSelectedQuest())
    }

    func stopSelectedQuest() {
        journalMenu.applied(journalMenu.journal.stopSelectedQuest())
    }

    func setSelectedQuestStage(_ index: Int) {
        journalMenu.applied(journalMenu.journal.setSelectedQuestStage(index))
    }

    func setSelectedQuestObjective(_ index: Int, displayed: Bool) {
        journalMenu.applied(
            journalMenu.journal.setSelectedQuestObjective(index, displayed: displayed)
        )
    }

    func journalAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        journalMenu.game.scripts.questAliasTable(editorID: editorID)
    }

    func toggleSelectedQuestTracking() {
        journalMenu.applied(journalMenu.journal.toggleSelectedTracking())
    }

    func showSelectedQuestOnMap() {
        guard let quest = journalMenu.journal.selectedEntry()?.quest.formID else { return }
        journalMenu.close()
        journalMenu.game.mapMenu.showQuestTarget(quest: quest)
    }
}

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
        guard movieLoaded, let runtime = game.renderer?.swfRuntime else { return nil }
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
