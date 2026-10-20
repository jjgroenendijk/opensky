// The dialogue menu: `dialoguemenu.swf` over `DialogueMenuModel`. Every
// conversation step is a `DialogueCoordinator` call. The menu leaves the world
// running while the player reads the list. Each run is said in the speaker's
// voice, and its end moves the menu on. A spoken line goes into the HUD's
// subtitle field once the HUD movie is back. See docs/engine/dialogue-menu.md.

import Foundation
import OpenSkyActorPresentation
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState

/// What `DialogueMenuController` reads from the session. `GameViewController` conforms.
@MainActor
protocol DialogueMenuHost: MenuInputConsumer {
    var audio: AudioCoordinator { get }
    var dialogue: DialogueCoordinator { get }
    var dialogueCamera: DialogueCameraController { get }
    var dialogueWorld: DialogueWorldAdapter { get }
    var faceMorphs: FaceMorphCoordinator { get }
    var headTracking: HeadTrackingCoordinator { get }
    var hud: HUDCoordinator { get }
    var menuMode: MenuModeController { get }
    var renderer: Renderer? { get }
    var storyWorld: StoryWorldAdapter { get }
    var streamer: CellStreamer? { get }
    var subtitles: SubtitleCoordinator { get }
    var swfMovies: SWFMovieSource { get }
}

/// Holds the conversation's menu model and movie state for `game`.
final class DialogueMenuController {
    static let identifier: MenuIdentifier = "Dialogue Menu"
    /// Measured with `openskycli swf dialogue-menu`: the list's slide-in ends
    /// before `eMenuState` reaches `TOPIC_LIST_SHOWN`.
    static let activationTicks = 30

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Dialogue"
    )

    unowned let game: any DialogueMenuHost
    private(set) var model = DialogueMenuModel.empty
    private(set) var isOpen = false
    let movie: MenuMovieSession

    init(game: any DialogueMenuHost) {
        self.game = game
        movie = MenuMovieSession(
            movies: game.swfMovies, hud: game.hud, label: "dialogue movie", logger: Self.logger
        ) { [unowned game] in game.renderer }
    }

    var movieLoaded: Bool {
        movie.isLoaded
    }

    var movieError: String? {
        movie.error
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
        guard !isOpen else { return }
        if let goodbye = dialogue.forcedGoodbye(for: speaker) {
            game.storyWorld.say(goodbye, speaker: speaker)
            return
        }
        guard let runtime = dialogue.begin(with: speaker) else { return }
        model = DialogueMenuModel.build(
            speaker: speaker,
            name: game.dialogueWorld.speakerLabel(for: speaker),
            runtime: runtime,
            strings: dialogue.strings
        )
        isOpen = true
        if model.state == .greeting, let info = model.line?.info {
            game.dialogueWorld.run(dialogue.recordGreeting(info, speaker: speaker))
            speakCurrentRun()
        }
        game.headTracking.setLookTarget(.player, for: speaker)
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
        if let speaker = model.speakerKey {
            game.audio.stopSpeaking(speaker)
            game.headTracking.setLookTarget(nil, for: speaker)
        }
        if let face = speakerFace {
            game.faceMorphs.clearEmotion(on: face)
        }
        dialogue.endConversation()
        model.showTopicList()
        game.menuMode.dismiss(Self.identifier)
        // Hands the view and the speaker back, unless the panel forces the camera.
        game.dialogueCamera.refreshFocus()
        movie.stop()
        publishSubtitle()
    }

    // MARK: - Input

    /// The engine model owns the selection: `TopicList.SetSelectedTopic` takes
    /// no row index, so there is no movie cursor to read back. The movie still
    /// gets the key for its focus art and sounds.
    func route(_ event: MenuInputEvent) {
        guard isOpen else { return }
        if case .button(.cancel) = event {
            let walkAway = model.state == .topicList
                ? model.speakerKey.flatMap { speaker in
                    dialogue.walkAway(speaker: speaker).map { ($0, speaker) }
                }
                : nil
            close()
            if let (info, speaker) = walkAway {
                game.storyWorld.say(info, speaker: speaker)
            }
            return
        }
        if let renderer = movie.loadedRenderer {
            do {
                _ = try DialogueMenuMovieBridge.send(event, renderer: renderer)
            } catch {
                movie.record(error)
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

    /// Enter on a line steps to its next run, then hands the list back. The end
    /// of a run's voice file does the same.
    private func advance() {
        guard model.state == .topicList else {
            if model.advanceResponse() {
                speakCurrentRun()
            } else {
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
        say(entry.info)
    }

    private func say(_ id: FormID) {
        guard let speaker = model.speakerKey else {
            dialogue.lastOutcome = "no dialogue index loaded"
            return
        }
        let chosen = dialogue.choose(id, speaker: speaker)
        game.dialogueWorld.run(chosen.commands)
        guard let info = chosen.value else { return }
        model.beginResponse(
            info: id,
            runs: DialogueMenuModel.responseRuns(
                dialogue.index?.responseSource(ofInfo: id) ?? info,
                strings: dialogue.strings
            )
        )
        speakCurrentRun()
    }

    /// Skipping the last run cuts its voice off, as skipping the text does.
    private func finishResponse() {
        if let speaker = model.speakerKey {
            game.audio.stopSpeaking(speaker)
        }
        switch dialogue.finishResponse(speaker: model.speakerKey) {
        case .close:
            close()
            return
        case let .continueWith(info):
            say(info)
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
        movie.start(MenuMovie(
            path: DialogueMenuMovieBridge.moviePath,
            activationTicks: Self.activationTicks,
            prepare: DialogueMenuMovieBridge.prepare(runtime:),
            activate: { [weak self] runtime in
                DialogueMenuMovieBridge.activate(runtime: runtime) { [weak self] in
                    self?.close()
                }
            },
            didLoad: { [weak self] in self?.publishModel() }
        ))
    }

    private func publishModel() {
        guard movieLoaded else {
            publishSubtitle()
            return
        }
        let model = model
        let showsSubtitle = game.subtitles.settings.dialogue
        movie.publish { runtime in
            DialogueMenuMovieBridge.publish(model, runtime: runtime, showsSubtitle: showsSubtitle)
        }
    }

    /// Reaches the HUD only after the menu closed; this clears a line so it
    /// does not outlive its menu. While the menu is up, its own
    /// `SubtitleText` carries the line.
    private func publishSubtitle() {
        guard game.hud.isLoaded, let renderer = game.renderer else { return }
        let subtitle = isOpen && game.subtitles.settings.dialogue ? model.subtitle : nil
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

/// Speech and the speaker's face, outside the class body for its length cap.
extension DialogueMenuController {
    /// Says the run on screen in the speaker's voice. A run with no voice file
    /// waits for Enter.
    private func speakCurrentRun() {
        guard let speaker = model.speakerKey, let line = model.line else { return }
        showEmotion(of: line)
        let paths = game.storyWorld.voicePaths(of: line.info, speaker: speaker)
        guard paths.indices.contains(line.index) else {
            game.audio.stopSpeaking(speaker)
            return
        }
        game.audio.speak([paths[line.index]], speaker: speaker) { [weak self] in
            self?.voiceEnded(line)
        }
    }

    private func voiceEnded(_ line: DialogueResponseLine) {
        guard isOpen, model.line == line else { return }
        advance()
        publishModel()
        publishSubtitle()
    }

    /// The placed actor whose face the speaker's expression goes on.
    private var speakerFace: FormID? {
        model.speakerKey.flatMap { game.streamer?.referenceEntry(key: $0)?.placedActor?.formID }
    }

    /// Puts the emotion of the run on screen (INFO `TRDT`) on the speaker's face.
    private func showEmotion(of line: DialogueResponseLine) {
        guard
            let face = speakerFace,
            let info = dialogue.runtime?.dialogue.info(line.info),
            info.responses.indices.contains(line.index)
        else { return }
        let response = info.responses[line.index]
        game.faceMorphs.showEmotion(
            response.emotion, value: response.emotionValue, on: face,
            now: game.renderer?.animationTime ?? 0
        )
    }
}
