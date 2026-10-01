// The journal: the Quests page of `quest_journal.swf` over `JournalMenuModel`.
// The system menu is the same movie, so its bridge makes the lifecycle calls
// and carries the input, and the two cannot be open at once. Every quest
// change is a `JournalCoordinator` call. See docs/engine/journal.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import OSLog

/// Holds the journal's page model and movie state for `game`.
final class JournalMenuController {
    static let identifier: MenuIdentifier = "Journal"

    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Journal"
    )

    unowned let game: GameViewController
    private(set) var model = JournalMenuModel.empty
    private(set) var isOpen = false
    private(set) var movieLoaded = false
    private(set) var movieError: String?

    init(game: GameViewController) {
        self.game = game
    }

    private var journal: JournalCoordinator {
        game.journal
    }

    // MARK: - Lifecycle

    func open() {
        guard !isOpen else { return }
        isOpen = true
        refreshModel()
        game.menuMode.inputConsumer = game
        game.menuMode.present(Self.identifier)
        startMovie()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        game.menuMode.dismiss(Self.identifier)
        if movieLoaded {
            stopMovie()
        }
    }

    /// Selects the quest the panel names. The page then shows its objectives.
    func setEditorID(_ editorID: String) {
        guard editorID != journal.editorID else { return }
        journal.editorID = editorID
        refreshModel()
        publishModel()
    }

    func setShowsCompleted(_ flag: Bool) {
        model.setShowsCompleted(flag)
        publishModel()
    }

    /// Rebuilds the page after a quest change that ran.
    func applied(_ ran: Bool) {
        guard ran else { return }
        refreshModel()
        publishModel()
    }

    /// Keeps the current selection and list.
    private func refreshModel() {
        guard let runtime = journal.runtime else {
            model = .empty
            return
        }
        model = JournalMenuModel.build(
            runtime: runtime,
            strings: journal.strings,
            aliases: aliasNaming(runtime: runtime),
            showsCompleted: model.showsCompleted,
            selectedIndex: max(model.selectedIndex, 0)
        )
        let wanted = journal.selectedEditorID.lowercased()
        guard
            !wanted.isEmpty,
            let row = model.entries.firstIndex(where: { $0.editorID.lowercased() == wanted })
        else {
            return
        }
        model.select(row)
    }

    /// Names an alias by its fill, but only while that reference is in a loaded
    /// cell. Otherwise the page shows the tag as written.
    private func aliasNaming(runtime: QuestRuntime) -> QuestAliasNaming {
        let aliases = runtime.aliasResolution()
        return QuestAliasNaming { [weak self] quest, aliasID in
            // Only the page build calls this, on the main actor beside the
            // streamer. The assert traps if a caller moves it off.
            MainActor.assumeIsolated {
                guard
                    let streamer = self?.game.streamer,
                    let key = aliases.reference(alias: aliasID, in: quest),
                    let entry = streamer.referenceEntry(key: key),
                    let name = streamer.interactionName(reference: entry.formID),
                    !name.isEmpty
                else {
                    return nil
                }
                return name
            }
        }
    }

    // MARK: - Input

    /// The movie gets the event first, so its tab strip still switches pages.
    /// Its title-list selection is then read back into the model.
    func route(_ event: MenuInputEvent) {
        guard isOpen else { return }
        if case .button(.cancel) = event {
            close()
            return
        }
        guard movieLoaded, let renderer = game.renderer else {
            applyFallback(event)
            return
        }
        do {
            _ = try SystemMenuMovieBridge.send(event, renderer: renderer)
            let selected = renderer.swfRuntime.flatMap { runtime in
                QuestJournalMovieBridge.selectedIndex(
                    runtime: runtime, atPath: QuestJournalMovieBridge.titleListPath
                )
            }
            if let selected {
                model.select(selected)
            } else {
                applyFallback(event)
            }
            publishModel()
        } catch {
            movieError = String(describing: error)
            Self.logger.error(
                "[ERROR] journal input: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Without a movie the panel's Up and Down still move the selection.
    private func applyFallback(_ event: MenuInputEvent) {
        switch event {
        case .move(.up): model.moveSelection(by: -1)
        case .move(.down): model.moveSelection(by: 1)
        default: break
        }
    }

    // MARK: - Movie

    /// A missing install or a failed movie degrades to a readout, never to a
    /// thrown error out of a control action.
    private func startMovie() {
        guard let renderer = game.renderer, let loader = game.swfMovies.loader else {
            movieLoaded = false
            movieError = "No game data located."
            return
        }
        do {
            // The renderer owns one SWF layer; this takes it from the HUD.
            game.hud.suspend()
            let scene = try loader.load(path: QuestJournalMovieBridge.moviePath)
            try renderer.setSWFMovie(scene)
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime(
                prepare: SystemMenuMovieBridge.prepare(runtime:)
            )
            guard started != nil else {
                movieLoaded = false
                movieError = "SWF runtime unavailable."
                return
            }
            try renderer.updateSWFRuntime { runtime in
                SystemMenuMovieBridge.activate(runtime: runtime) { [weak self] in
                    self?.close()
                }
                QuestJournalMovieBridge.activate(runtime: runtime)
            }
            // The same fade the system menu measured.
            for _ in 0 ..< SystemMenuMovieBridge.activationTicks {
                try renderer.advanceSWFRuntime()
            }
            movieLoaded = true
            movieError = nil
            publishModel()
        } catch {
            movieLoaded = false
            movieError = String(describing: error)
            Self.logger.error(
                "[ERROR] journal movie: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func stopMovie() {
        movieLoaded = false
        movieError = nil
        game.hud.start()
    }

    private func publishModel() {
        guard movieLoaded, let renderer = game.renderer else { return }
        do {
            try renderer.updateSWFRuntime { runtime in
                QuestJournalMovieBridge.publish(model, runtime: runtime)
            }
        } catch {
            movieError = String(describing: error)
            Self.logger.error(
                "[ERROR] journal publish: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Snapshot

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
                : SWFDrawStats()
        )
    }

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

    private func movieValue<Value>(_ read: (SWFMovieRuntime) -> Value) -> Value? {
        guard movieLoaded, let runtime = game.renderer?.swfRuntime else { return nil }
        return read(runtime)
    }

    private var diagnostics: QuestJournalDiagnostics? {
        movieValue(QuestJournalMovieBridge.diagnostics(runtime:))
    }
}

extension JournalMenuController: JournalWorld {
    var questRuntime: QuestRuntime? {
        game.scripts.bridge?.questRuntime as? QuestRuntime
    }

    func loadStrings() -> LocalizedStrings? {
        game.localizedStringsLoader?()
    }
}
