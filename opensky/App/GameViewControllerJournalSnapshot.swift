// The journal panel's sample (issue #184). Satellite of
// GameViewControllerJournal.swift, which owns the presentation and the
// mutations; this file only reads.
//
// One sample per refresh, exactly like `ScriptsSnapshot`: the panel refreshes
// every readout together, so the text stays a pure function of a single engine
// sample and two sections can never show a half-updated session.

import AppKit

extension GameViewController {
    var journalSnapshot: JournalControlSnapshot {
        guard let runtime = journalQuestRuntime else {
            return .empty
        }
        let quests = runtime.quests.journalQuests()
        let states = quests.compactMap { quest -> (Quest, QuestRuntimeState)? in
            guard let state = try? runtime.state(of: quest.formID) else { return nil }
            return (quest, state)
        }
        let interesting = states.filter { $0.1.isRunning || $0.1.isCompleted }
        let rows = interesting.prefix(JournalControlSnapshot.rowLimit).map(Self.journalRow)
        let selected = journal.editorID.trimmingCharacters(in: .whitespaces)
        let selectedEntry = journal.model.entries.first { $0.editorID == selected }
        return JournalControlSnapshot(
            hasQuestIndex: !runtime.quests.isEmpty,
            questCount: quests.count,
            runningCount: states.count { $0.1.isRunning },
            completedCount: states.count { $0.1.isCompleted },
            rows: Array(rows),
            droppedRowCount: max(interesting.count - rows.count, 0),
            selectedEditorID: selected,
            selectedRow: selectedQuestRow(runtime: runtime, editorID: selected),
            selectedObjectives: (selectedEntry?.objectives ?? []).map {
                "\($0.index) \($0.text)"
            },
            selectedLogEntries: selectedEntry?.logEntries ?? [],
            lastOutcome: journal.lastOutcome,
            isOpen: journal.isOpen,
            openMenus: menuMode.stack.identifiers.map(\.name),
            showsCompleted: journal.model.showsCompleted,
            listedQuestCount: journal.model.entries.count,
            selectedIndex: journal.model.selectedIndex,
            movieLoaded: journal.movieLoaded,
            movieError: journal.movieError,
            movieQuestRows: journalMovieValue(QuestJournalMovieBridge.questLabels)?.count ?? 0,
            movieObjectiveRows: journalMovieValue(
                QuestJournalMovieBridge.objectiveLabels
            )?.count ?? 0,
            movieTitleText: journalMovieValue(QuestJournalMovieBridge.titleText)
                .flatMap(\.self),
            movieObjectiveFrames: journalMovieValue(
                QuestJournalMovieBridge.objectiveEntryFrames
            ) ?? [],
            movieFaults: journalDiagnostics?.faults ?? 0,
            movieMissingNames: journalDiagnostics?.missingNames ?? 0,
            movieUnhandledInvokes: journalDiagnostics?.unhandledInvokes ?? 0,
            movieDrawStats: journal.movieLoaded
                ? (renderer?.lastSWFDrawStats ?? SWFDrawStats())
                : SWFDrawStats()
        )
    }

    /// One quest as the panel lists it, including the objectives it declares
    /// but has not touched: an untouched objective is the interesting case when
    /// a quest is running and its page is empty.
    private static func journalRow(
        _ quest: Quest,
        _ state: QuestRuntimeState
    ) -> JournalQuestRow {
        JournalQuestRow(
            editorID: quest.editorID ?? quest.formID.description,
            title: JournalMenuModel.fallbackTitle(for: quest),
            kind: quest.kind.name,
            isRunning: state.isRunning,
            isCompleted: state.isCompleted,
            stage: state.currentStage,
            declaredStages: Array(Set(quest.stages.map(\.index))).sorted(),
            objectives: quest.objectives.map { objective in
                let display = state.objective(objective.index)
                let word = if display.isFailed {
                    "failed"
                } else if display.isCompleted {
                    "completed"
                } else if display.isDisplayed {
                    "displayed"
                } else {
                    "untouched"
                }
                return "\(objective.index) \(word)"
            }
        )
    }

    private func selectedQuestRow(
        runtime: QuestRuntime,
        editorID: String
    ) -> JournalQuestRow? {
        guard
            !editorID.isEmpty,
            let quest = runtime.quests.quest(editorID: editorID),
            let state = try? runtime.state(of: quest.formID)
        else {
            return nil
        }
        return Self.journalRow(quest, state)
    }

    /// Reads one value off the live movie runtime, or nil when no movie is up.
    private func journalMovieValue<Value>(
        _ read: (SWFMovieRuntime) -> Value
    ) -> Value? {
        guard journal.movieLoaded, let runtime = renderer?.swfRuntime else { return nil }
        return read(runtime)
    }

    private var journalDiagnostics: QuestJournalDiagnostics? {
        journalMovieValue(QuestJournalMovieBridge.diagnostics(runtime:))
    }
}
