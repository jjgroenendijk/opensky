public import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDialogue
public import OpenSkyDialogueInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyQuests
import OpenSkyQuestsInterface
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `StorySceneLinesAdapter` reads from the session.
@MainActor
public protocol StorySceneLinesHost: AnyObject, SendableMetatype {
    var audio: any AudioPort { get }
    var dialogue: any DialoguePort { get }
    var dialogueWorld: any DialogueWorldPort { get }
    var faceMorphs: any FaceMorphPort { get }
    var headTracking: any HeadTrackingPort { get }
    var renderer: (any RendererPort)? { get }
    var streamer: any CellStreamerPort { get }
    var subtitles: any SubtitlePort { get }
    var idles: any IdlePort { get }
}

/// Part of `StoryWorldAdapter`, over its own narrow host.
public struct StorySceneLinesAdapter {
    public let game: any StorySceneLinesHost
    public let state: StoryPartState
    public let sceneCast: StorySceneCastAdapter
    public let now: () -> Date
}

extension StorySceneLinesAdapter {
    /// The line's seconds plus `fGameplayVoiceFilePadding`, the gap before the next line.
    /// A speaker with no loaded body ends the line at once, as the reference game does.
    public func lineDuration(of info: TopicInfo, speaker: ReferenceKey) -> Float? {
        let streamer = game.streamer
        if
            speaker != .player,
            streamer.residentActorEntry(key: speaker) == nil
        {
            return 0
        }
        let texts = responseTexts(of: info)
        let speech = game.dialogue.speechTimers
        let seconds = state.voiceTimer.map {
            $0.duration(
                of: info, voiceType: voiceTypeName(of: speaker), texts: texts, speech: speech
            )
        } ?? SceneCore.lineDuration(texts: texts, speech: speech)
        return seconds.map { speech.padded($0) + max(speech.speechDelay, 0) }
    }

    /// A shared INFO (`DNAM`) says its target's text.
    private func responseTexts(of info: TopicInfo) -> [String?] {
        let info = game.dialogue.index?.responseSource(ofInfo: info.formID) ?? info
        let strings = game.dialogue.strings
        return info.responses.map { response in
            strings.flatMap { response.resolvedText(using: $0) }
        }
    }

    /// The `VTCK` editor ID, which names the voice folder.
    private func voiceTypeName(of speaker: ReferenceKey) -> String? {
        guard
            let voice = game.dialogueWorld.residentVoiceTypes()[speaker],
            let record = game.dialogue.index?.voiceType(voice)
        else { return nil }
        return record.editorID
    }

    /// The voice files `speaker` says `info` with, in response order. Empty
    /// without game data or a known voice type.
    public func voicePaths(of info: FormID, speaker: ReferenceKey) -> [String] {
        guard
            let voiceLocator = state.voiceLocator,
            let record = voiceLocator.dialogue.info(info),
            let voiceType = voiceTypeName(of: speaker)
        else { return [] }
        return voiceLocator.lines(info: record, voiceType: voiceType).map(\.path)
    }

    /// A speaker that is not loaded has no body to speak from, so its line is neither
    /// heard nor subtitled. The scene still times the line.
    public func run(_ commands: [SceneCommand]) {
        for case let .speak(line) in commands {
            speak(
                info: line.info,
                speaker: line.speaker,
                lookAt: line.lookAt,
                seconds: line.seconds
            )
        }
    }

    /// Says an already recorded line outside the menu, looking at the player.
    public func say(_ id: FormID, speaker: ReferenceKey) {
        guard let info = game.dialogue.runtime?.dialogue.info(id) else { return }
        let seconds = lineDuration(of: info, speaker: speaker) ?? SceneLine.defaultSeconds
        speak(info: id, speaker: speaker, lookAt: .player, seconds: seconds)
    }

    /// Voices, subtitles, and shows one dialogue line, as a scene or a Say procedure does,
    /// after the `fSpeechDelay` pause.
    public func speak(
        info id: FormID,
        speaker: ReferenceKey,
        lookAt: ReferenceKey?,
        seconds: Float
    ) {
        let delay = Double(max(game.dialogue.speechTimers.speechDelay, 0))
        guard delay > 0 else {
            startLine(info: id, speaker: speaker, lookAt: lookAt, seconds: seconds)
            return
        }
        state.delayedLines.append(DelayedLine(
            due: sceneCast.sceneSeconds + delay, info: id, speaker: speaker, lookAt: lookAt,
            seconds: max(seconds - Float(delay), 0)
        ))
    }

    public func startLine(
        info id: FormID,
        speaker: ReferenceKey,
        lookAt: ReferenceKey?,
        seconds: Float
    ) {
        guard game.dialogueWorld.headPosition(of: speaker) != nil else { return }
        game.audio.speak(voicePaths(of: id, speaker: speaker), speaker: speaker)
        let info = game.dialogue.runtime?.dialogue.info(id)
        if let lookAt {
            game.headTracking.setLookTarget(
                lookAt, for: speaker, seconds: seconds, dialogue: true
            )
        }
        if
            let response = info?.responses.first,
            let face = game.streamer.referenceEntry(key: speaker)?.placedActor?.formID
        {
            game.faceMorphs.showEmotion(
                response.emotion, value: response.emotionValue, on: face,
                now: game.renderer?.animationTime ?? 0, seconds: seconds
            )
        }
        playResponseIdles(of: id, speaker: speaker, listener: lookAt)
        let text = info
            .map { responseTexts(of: $0).compactMap(\.self).joined(separator: " ") } ?? ""
        game.subtitles.say(
            text, kind: .general, seconds: Double(seconds),
            now: now().timeIntervalSinceReferenceDate
        )
    }

    public func playResponseIdles(of info: FormID, speaker: ReferenceKey, listener: ReferenceKey?) {
        guard
            let dialogue = game.dialogue.runtime?.dialogue,
            let source = dialogue.responseSource(ofInfo: info)
        else { return }
        let resolver = dialogue.sourceResolver(ofInfo: source.formID)
        let responses = source.responses
        if let idle = responses.lazy.compactMap(\.speakerIdle).first.flatMap(resolver.resolve) {
            game.idles.fireIdle(idle, on: speaker, ignoringConditions: true)
        }
        if
            let listener, listener != speaker,
            let idle = responses.lazy.compactMap(\.listenerIdle).first.flatMap(resolver.resolve)
        {
            game.idles.fireIdle(idle, on: listener, ignoringConditions: true)
        }
    }
}
