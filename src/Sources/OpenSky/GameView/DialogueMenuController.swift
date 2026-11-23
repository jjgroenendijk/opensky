// The dialogue menu: `dialoguemenu.swf` over `DialogueMenuModel`. Every
// conversation step is a `DialogueCoordinator` call. The menu leaves the world
// running while the player reads the list. Each run is said in the speaker's
// voice, and its end moves the menu on. A spoken line goes into the HUD's
// subtitle field once the HUD movie is back. See docs/engine/dialogue-menu.md.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `DialogueMenuController` reads from the session. `GameViewController` conforms.
@MainActor
protocol DialogueMenuHost: MenuInputConsumer, SendableMetatype {
    var dialogue: any DialoguePort { get }
    var dialogueCamera: any DialogueCameraPort { get }
    var dialogueWorld: any DialogueWorldPort { get }
    var furniture: any FurniturePort { get }
    var headTracking: any HeadTrackingPort { get }
    var menuMode: any MenuModePort { get }
    var storyWorld: any StoryWorldPort { get }
    var journalMenu: any JournalMenuPort { get }
    var streamer: any CellStreamerPort { get }
    var swfMovies: any SWFMovieSourcePort { get }
    var worldRecords: (any WorldRecordsPort)? { get }
}

/// Holds the conversation's menu model and movie state for `game`.
final class DialogueMenuController {
    static let identifier = MenuIdentifier.dialogueMenu
    /// Measured with `openskycli menu dialogue`: the list's slide-in ends
    /// before `eMenuState` reaches `TOPIC_LIST_SHOWN`.
    static let activationTicks = 30

    static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Dialogue"
    )

    unowned let game: any DialogueMenuHost
    var model: OpenSkyMenus.DialogueMenuModel = .empty
    var isOpen = false
    let movie: MenuMovieSession

    let speechHost: any DialogueMenuSpeechHost

    var speech: DialogueMenuController.SpeechAdapter {
        DialogueMenuController.SpeechAdapter(owner: self, game: speechHost)
    }

    init(game: some DialogueMenuHost & DialogueMenuSpeechHost) {
        speechHost = game
        self.game = game
        movie = MenuMovieSession(
            movies: game.swfMovies, hud: game.hud, label: "dialogue movie", logger: Self.logger
        ) { [unowned game] in game.renderer }
    }

    var movieLoaded: Bool {
        movie.isLoaded
    }

    var dialogue: any DialoguePort {
        game.dialogue
    }

    /// The open conversation's speaker, else the crosshair's Talk target.
    var speakerOrTarget: ReferenceKey? {
        model.speakerKey ?? game.streamer.talk.speaker
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
        // An actor still in dialogue mode goes on without a new greeting.
        let continues = dialogue.dialogueMode.isTalking(speaker)
        guard let runtime = dialogue.begin(with: speaker) else { return }
        game.furniture.greet(speaker)
        model = DialogueMenuModel.build(
            speaker: speaker,
            name: game.dialogueWorld.speakerLabel(for: speaker),
            runtime: runtime,
            strings: dialogue.strings,
            tags: textTags(speaker: speaker),
            greets: !continues
        )
        isOpen = true
        if model.state == .greeting, let info = model.line?.info {
            game.dialogueWorld.run(dialogue.recordGreeting(info, speaker: speaker))
            speech.speakCurrentRun()
        }
        game.headTracking.setLookTarget(.player, for: speaker, dialogue: true)
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
        speech.startMovie()
    }

    func openFromCrosshair() {
        guard !isOpen else { return }
        guard let speaker = game.streamer.talk.speaker else {
            dialogue.lastOutcome = "no actor under the crosshair"
            return
        }
        begin(with: speaker)
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
        speech.publishModel()
        speech.publishSubtitle()
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
    func advance() {
        guard model.state == .topicList else {
            if model.advanceResponse() {
                speech.speakCurrentRun()
            } else {
                speech.finishResponse()
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
        speech.say(entry.info)
    }
}

/// Speech and the speaker's face, outside the class body for its length cap.
extension DialogueMenuController {}

extension DialogueMenuController {
    func tick(now: Double) {
        guard isOpen else { return }
        movie.advance(now: now)
    }
}

/// The text-replacement tags of the open conversation, with the two the engine fills from
/// the speaker ([text](docs/engine/dialogue-menu.md#text)).
extension DialogueMenuController {
    func textTags(speaker: ReferenceKey?) -> DialogueTextTags {
        let quests = game.worldRecords?.questStore
        return DialogueTextTags(
            naming: game.journalMenu.currentAliasNaming ?? .none,
            values: speaker.map(engineTagValues) ?? [:]
        ) { quests?.quest($0) }
    }

    /// `<CrimeGold>`, the player's bounty with the speaker's crime faction, and
    /// `<BribeCost>`, the gold the speaker asks as a bribe, in whole gold.
    private func engineTagValues(_ speaker: ReferenceKey) -> [String: String] {
        guard let context = dialogue.runtime?.conditionContext(speaker: speaker) else { return [:] }
        var values: [String: String] = [:]
        if let gold = context.playerCrimeGold(owedTo: speaker) {
            values["CrimeGold"] = String(gold)
        }
        if
            let bribe = context[resolution: SpeechCheckResolution.self]
                .bribeAmount(of: speaker, actors: context.actors)
        {
            values["BribeCost"] = String(Int(max(bribe, 0)))
        }
        return values
    }
}
