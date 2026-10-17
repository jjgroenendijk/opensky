// The journal: the Quests page of `quest_journal.swf` over `JournalMenuModel`.
// The system menu is the same movie, so its bridge makes the lifecycle calls
// and carries the input, and the two cannot be open at once. Every quest
// change is a `JournalCoordinator` call. See docs/engine/journal.md.

import Foundation
import OpenSkyFormatsCore
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

/// Holds the journal's page model and movie state for `game`.
final class JournalMenuController {
    static let identifier: MenuIdentifier = "Journal"

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Journal"
    )

    unowned let game: GameViewController
    private(set) var model = JournalMenuModel.empty
    private(set) var isOpen = false
    let movie: MenuMovieSession

    init(game: GameViewController) {
        self.game = game
        movie = MenuMovieSession(
            movies: game.swfMovies, hud: game.hud, label: "journal movie", logger: Self.logger
        ) { [unowned game] in game.renderer }
    }

    var movieLoaded: Bool {
        movie.isLoaded
    }

    var movieError: String? {
        movie.error
    }

    var journal: JournalCoordinator {
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
        movie.stop()
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
        let wantedID = runtime.quests.quest(editorID: journal.selectedEditorID)?.formID
        let row = model.entries.firstIndex { entry in
            entry.editorID.lowercased() == wanted
                || wantedID.map { entry.miscQuests.contains($0) } == true
        }
        guard !wanted.isEmpty, let row else { return }
        model.select(row)
    }

    /// Names an alias by its fill, but only while that reference is in a loaded
    /// cell. Otherwise the page shows the tag as written.
    func aliasNaming(runtime: QuestRuntime) -> QuestAliasNaming {
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
        guard let renderer = movie.loadedRenderer else {
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
            movie.record(error)
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

    /// The renderer owns one SWF layer; this takes it from the HUD. The fade is
    /// the one the system menu measured.
    private func startMovie() {
        movie.start(MenuMovie(
            path: QuestJournalMovieBridge.moviePath,
            activationTicks: SystemMenuMovieBridge.activationTicks,
            prepare: SystemMenuMovieBridge.prepare(runtime:),
            activate: { [weak self] runtime in
                SystemMenuMovieBridge.activate(runtime: runtime) { [weak self] in
                    self?.close()
                }
                QuestJournalMovieBridge.activate(runtime: runtime)
                self?.registerMovieCalls(runtime: runtime)
            },
            didLoad: { [weak self] in self?.publishModel() }
        ))
    }

    private func registerMovieCalls(runtime: SWFMovieRuntime) {
        QuestJournalMovieBridge.registerCalls(
            runtime: runtime,
            toggleTracking: { [weak self] quest in
                let tracked = self?.journal.toggleTracking(quest)
                self?.refreshModel()
                return tracked
            },
            showOnMap: { [weak self] quest, objective in
                self?.close()
                self?.game.mapMenu.showQuestTarget(quest: quest, objective: objective)
            }
        )
        let stats = JournalStatRow.rows(game.worldState.miscStats)
        QuestJournalMovieBridge.publishStats(stats, runtime: runtime)
    }

    private func publishModel() {
        let model = model
        movie.publish { QuestJournalMovieBridge.publish(model, runtime: $0) }
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
