// The dialogue menu: `dialoguemenu.swf` over `DialogueMenuModel`. Every
// conversation step is a `DialogueCoordinator` call. The menu leaves the world
// running while the player reads the list. A spoken line goes into the HUD's
// subtitle field once the HUD movie is back. See docs/engine/dialogue-menu.md.

import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import OSLog

/// Holds the conversation's menu model and movie state for `game`.
final class DialogueMenuController {
    static let identifier: MenuIdentifier = "Dialogue Menu"
    /// Measured with `openskycli swf dialogue-menu`: the list's slide-in ends
    /// before `eMenuState` reaches `TOPIC_LIST_SHOWN`.
    static let activationTicks = 30

    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Dialogue"
    )

    unowned let game: GameViewController
    private(set) var model = DialogueMenuModel.empty
    private(set) var isOpen = false
    private(set) var movieLoaded = false
    private(set) var movieError: String?

    init(game: GameViewController) {
        self.game = game
    }

    var dialogue: DialogueCoordinator {
        game.dialogue
    }

    /// The open conversation's speaker, else the crosshair's Talk target.
    var speakerOrTarget: ReferenceKey? {
        model.speakerKey ?? game.streamer?.talk.speaker
    }

    // MARK: - Lifecycle

    /// A speaker with nothing to say still opens the menu. The condition trace
    /// beside the list says why, and the use key does not seem dead.
    func begin(with speaker: ReferenceKey) {
        guard !isOpen, let runtime = dialogue.begin(with: speaker) else { return }
        model = DialogueMenuModel.build(
            speaker: speaker,
            name: game.dialogueWorld.speakerLabel(for: speaker),
            runtime: runtime,
            strings: dialogue.strings
        )
        isOpen = true
        if model.state == .greeting, let info = model.line?.info {
            dialogue.recordGreeting(info, speaker: speaker)
        }
        dialogue.lastOutcome = DialogueCore.openedText(
            speaker: model.speaker,
            topicCount: model.topics.count,
            rejectedCount: dialogue.selection.rejected.count
        )
        game.menuMode.inputConsumer = game
        // Voice, facing, lip sync, and the camera run on the world clock.
        game.menuMode.present(Self.identifier, policy: .leavesWorldRunning)
        // The first frame under the menu is already the conversation's shot.
        game.dialogueCamera.refreshFocus()
        startMovie()
    }

    func openFromCrosshair() {
        guard !isOpen else { return }
        guard let speaker = game.streamer?.talk.speaker else {
            dialogue.lastOutcome = "no actor under the crosshair"
            return
        }
        begin(with: speaker)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        dialogue.endConversation()
        model.showTopicList()
        game.menuMode.dismiss(Self.identifier)
        // Hands the view and the speaker back, unless the panel forces the camera.
        game.dialogueCamera.refreshFocus()
        if movieLoaded {
            stopMovie()
        } else {
            publishSubtitle()
        }
    }

    // MARK: - Input

    /// The engine model owns the selection: `TopicList.SetSelectedTopic` takes
    /// no row index, so there is no movie cursor to read back. The movie still
    /// gets the key for its focus art and sounds.
    func route(_ event: MenuInputEvent) {
        guard isOpen else { return }
        if case .button(.cancel) = event {
            close()
            return
        }
        if movieLoaded, let renderer = game.renderer {
            do {
                _ = try DialogueMenuMovieBridge.send(event, renderer: renderer)
            } catch {
                movieError = String(describing: error)
            }
        }
        apply(event)
        publishModel()
        publishSubtitle()
    }

    private func apply(_ event: MenuInputEvent) {
        switch event {
        case .move(.up): model.moveSelection(by: -1)
        case .move(.down): model.moveSelection(by: 1)
        case .button(.accept): advance()
        default: break
        }
    }

    /// Enter on a line steps to its next run, then hands the list back. Exact
    /// end-of-line timing waits for the playback clock.
    private func advance() {
        guard model.state == .topicList else {
            if !model.advanceResponse() {
                finishResponse()
            }
            return
        }
        chooseTopic()
    }

    private func chooseTopic() {
        guard let entry = model.selectedTopic else {
            dialogue.lastOutcome = "no topic selected"
            return
        }
        guard let speaker = model.speakerKey else {
            dialogue.lastOutcome = "no dialogue index loaded"
            return
        }
        guard let info = dialogue.choose(entry.info, speaker: speaker) else { return }
        model.beginResponse(
            info: entry.info,
            runs: DialogueMenuModel.responseRuns(info, strings: dialogue.strings)
        )
    }

    private func finishResponse() {
        switch dialogue.finishResponse(speaker: model.speakerKey) {
        case .close:
            close()
            return
        case let .topics(selection):
            if let runtime = dialogue.runtime {
                model.setTopics(
                    DialogueMenuModel.rows(selection, runtime: runtime, strings: dialogue.strings)
                )
            }
        case .unchanged:
            break
        }
        model.showTopicList()
    }

    // MARK: - Movie

    /// A missing install or a failed movie degrades to a readout, never to a
    /// conversation that cannot be left.
    private func startMovie() {
        guard let renderer = game.renderer, let loader = game.swfMovies.loader else {
            movieLoaded = false
            movieError = "No game data located."
            return
        }
        do {
            // The renderer owns one SWF layer; this takes it from the HUD.
            game.hud.suspend()
            let scene = try loader.load(path: DialogueMenuMovieBridge.moviePath)
            try renderer.setSWFMovie(scene)
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime(
                prepare: DialogueMenuMovieBridge.prepare(runtime:)
            )
            guard started != nil else {
                movieLoaded = false
                movieError = "SWF runtime unavailable."
                return
            }
            try renderer.updateSWFRuntime { runtime in
                DialogueMenuMovieBridge.activate(runtime: runtime) { [weak self] in
                    self?.close()
                }
            }
            for _ in 0 ..< Self.activationTicks {
                try renderer.advanceSWFRuntime()
            }
            movieLoaded = true
            movieError = nil
            publishModel()
        } catch {
            movieLoaded = false
            movieError = String(describing: error)
            Self.logger.error(
                "[ERROR] dialogue movie: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func stopMovie() {
        movieLoaded = false
        movieError = nil
        game.hud.start()
        publishSubtitle()
    }

    private func publishModel() {
        guard movieLoaded, let renderer = game.renderer else {
            publishSubtitle()
            return
        }
        do {
            try renderer.updateSWFRuntime { runtime in
                DialogueMenuMovieBridge.publish(model, runtime: runtime)
            }
        } catch {
            movieError = String(describing: error)
            Self.logger.error(
                "[ERROR] dialogue publish: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Reaches the HUD only after the menu closed; this clears a line so it
    /// does not outlive its menu. While the menu is up, its own
    /// `SubtitleText` carries the line.
    private func publishSubtitle() {
        guard game.hud.isLoaded, let renderer = game.renderer else { return }
        let subtitle = isOpen ? model.subtitle : nil
        do {
            try renderer.updateSWFRuntime { runtime in
                HUDMovieBridge.setSubtitleText(subtitle, runtime: runtime)
            }
        } catch {
            Self.logger.error(
                "[ERROR] dialogue subtitle: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
