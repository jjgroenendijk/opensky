import Foundation
import OpenSkyActorPresentation
import OpenSkyAIPackages
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

/// What `DialogueMenuController.SpeechAdapter` reads from the session.
@MainActor
protocol DialogueMenuSpeechHost: AnyObject {
    var audio: any AudioPort { get }
    var dialogueCamera: any DialogueCameraPort { get }
    var dialogueWorld: any DialogueWorldPort { get }
    var faceMorphs: any FaceMorphPort { get }
    var headTracking: any HeadTrackingPort { get }
    var hud: any HUDPort { get }
    var menuMode: any MenuModePort { get }
    var renderer: (any RendererPort)? { get }
    var storyWorld: any StoryWorldPort { get }
    var streamer: any CellStreamerPort { get }
    var subtitles: any SubtitlePort { get }
}

extension DialogueMenuController {
    /// Part of `DialogueMenuController`, over its own narrow host.
    struct SpeechAdapter {
        unowned let owner: DialogueMenuController
        unowned let game: any DialogueMenuSpeechHost
    }
}

extension DialogueMenuController.SpeechAdapter {
    func close() {
        guard owner.isOpen else { return }
        owner.isOpen = false
        if let speaker = owner.model.speakerKey {
            game.audio.stopSpeaking(speaker)
            game.headTracking.setLookTarget(nil, for: speaker)
        }
        if let face = speakerFace {
            game.faceMorphs.clearEmotion(on: face)
        }
        owner.dialogue.endConversation()
        owner.model.showTopicList()
        game.menuMode.dismiss(DialogueMenuController.identifier)
        // Hands the view and the speaker back, unless the readout forces the camera.
        game.dialogueCamera.refreshFocus()
        owner.movie.stop()
        publishSubtitle()
    }

    func say(_ id: FormID) {
        guard let speaker = owner.model.speakerKey else {
            owner.dialogue.lastOutcome = "no dialogue index loaded"
            return
        }
        let chosen = owner.dialogue.choose(id, speaker: speaker)
        game.dialogueWorld.run(chosen.commands)
        guard let info = chosen.value else { return }
        owner.model.beginResponse(
            info: id,
            runs: DialogueMenuModel.responseRuns(
                owner.dialogue.index?.responseSource(ofInfo: id) ?? info,
                strings: owner.dialogue.strings
            )
        )
        speakCurrentRun()
    }

    /// Skipping the last run cuts its voice off, as skipping the text does.
    func finishResponse() {
        if let speaker = owner.model.speakerKey {
            game.audio.stopSpeaking(speaker)
        }
        switch owner.dialogue.finishResponse(speaker: owner.model.speakerKey) {
        case .close:
            close()
            return
        case let .continueWith(info):
            say(info)
            return
        case let .topics(selection):
            if let runtime = owner.dialogue.runtime {
                owner.model.setTopics(
                    DialogueMenuModel.rows(
                        selection,
                        runtime: runtime,
                        strings: owner.dialogue.strings
                    )
                )
            }
        case .unchanged:
            break
        }
        owner.model.showTopicList()
    }

    // MARK: - Movie

    /// A missing install or a failed movie degrades to a readout, never to a
    /// conversation that cannot be left.
    func startMovie() {
        owner.movie.start(MenuMovie(
            path: DialogueMenuMovieBridge.moviePath,
            activationTicks: DialogueMenuController.activationTicks,
            prepare: DialogueMenuMovieBridge.prepare(runtime:),
            activate: { [weak owner] runtime in
                DialogueMenuMovieBridge.activate(runtime: runtime) { [weak owner] in
                    owner?.speech.close()
                }
            },
            didLoad: { [weak owner] in owner?.speech.publishModel() }
        ))
    }

    func publishModel() {
        guard owner.movieLoaded else {
            publishSubtitle()
            return
        }
        let model = owner.model
        let showsSubtitle = game.subtitles.settings.dialogue
        owner.movie.publish { runtime in
            DialogueMenuMovieBridge.publish(model, runtime: runtime, showsSubtitle: showsSubtitle)
        }
    }

    /// Reaches the HUD only after the menu closed; this clears a line so it
    /// does not outlive its menu. While the menu is up, its own
    /// `SubtitleText` carries the line.
    func publishSubtitle() {
        guard game.hud.isLoaded, let renderer = game.renderer else { return }
        let subtitle = owner.isOpen && game.subtitles.settings.dialogue ? owner.model.subtitle : nil
        do {
            try renderer.updateSWFRuntime { runtime in
                HUDMovieBridge.setSubtitleText(subtitle, runtime: runtime)
            }
        } catch {
            DialogueMenuController.logger.error(
                "[ERROR] dialogue subtitle: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Says the run on screen in the speaker's voice. A run with no voice file
    /// waits for Enter.
    func speakCurrentRun() {
        guard let speaker = owner.model.speakerKey, let line = owner.model.line else { return }
        showEmotion(of: line)
        let paths = game.storyWorld.voicePaths(of: line.info, speaker: speaker)
        guard paths.indices.contains(line.index) else {
            game.audio.stopSpeaking(speaker)
            return
        }
        game.audio.speak([paths[line.index]], speaker: speaker) { [weak owner] in
            owner?.speech.voiceEnded(line)
        }
    }

    private func voiceEnded(_ line: DialogueResponseLine) {
        guard owner.isOpen, owner.model.line == line else { return }
        owner.advance()
        publishModel()
        publishSubtitle()
    }

    /// The placed actor whose face the speaker's expression goes on.
    private var speakerFace: FormID? {
        owner.model.speakerKey
            .flatMap { game.streamer.referenceEntry(key: $0)?.placedActor?.formID }
    }

    /// Puts the emotion of the run on screen (INFO `TRDT`) on the speaker's face.
    private func showEmotion(of line: DialogueResponseLine) {
        guard
            let face = speakerFace,
            let info = owner.dialogue.runtime?.dialogue.info(line.info),
            info.responses.indices.contains(line.index)
        else { return }
        let response = info.responses[line.index]
        game.faceMorphs.showEmotion(
            response.emotion, value: response.emotionValue, on: face,
            now: game.renderer?.animationTime ?? 0
        )
    }
}
