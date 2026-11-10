import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCombatInterface
import OpenSkyDialogue
public import OpenSkyDialogueInterface
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import simd

/// What `StoryAmbientTalkAdapter` reads from the session.
@MainActor
public protocol StoryAmbientTalkHost: AnyObject, SendableMetatype {
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var dialogue: any DialoguePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var packages: any PackagePort { get }
    var perception: any PerceptionPort { get }
    var streamer: any CellStreamerPort { get }
    var scenes: any ScenePort { get }
}

/// Part of `StoryWorldAdapter`, over its own narrow host.
public struct StoryAmbientTalkAdapter {
    public let game: any StoryAmbientTalkHost
    public let state: StoryPartState
    public let sceneCast: StorySceneCastAdapter
    public let sceneLines: StorySceneLinesAdapter
}

extension StoryAmbientTalkAdapter {
    /// Frames between ambient speech passes, so each pass reads the actors a few times
    /// a second rather than every frame.
    public static let ambientSpeechInterval = 15

    /// Starts the lines whose delay has passed, then runs the ambient pass on its interval.
    public func tickAmbientSpeech() {
        let now = sceneCast.sceneSeconds
        let due = state.delayedLines.filter { $0.due <= now }
        state.delayedLines.removeAll { $0.due <= now }
        for line in due {
            sceneLines.startLine(
                info: line.info,
                speaker: line.speaker,
                lookAt: line.lookAt,
                seconds: line.seconds
            )
        }
        if game.streamer.dynamicBodies.lastPushCount > 0 {
            commentOnPlayer(.knockOver)
        }
        state.framesSinceAmbientSpeech += 1
        guard state.framesSinceAmbientSpeech >= Self.ambientSpeechInterval else { return }
        state.framesSinceAmbientSpeech = 0
        let elapsed = Float(now - (state.lastAmbientSpeechSeconds ?? now))
        state.lastAmbientSpeechSeconds = now
        guard let frame = ambientSpeechFrame(now: now) else { return }
        for line in game.dialogue.ambientLines(frame, seconds: elapsed) {
            sayAmbient(line)
        }
    }

    /// A witness near the player comments on `line`, such as a shout or a bow shot.
    public func commentOnPlayer(_ line: NPCSpeechLine) {
        guard
            game.dialogue.isSharedReady(line, now: sceneCast.sceneSeconds),
            let frame = ambientSpeechFrame(now: sceneCast.sceneSeconds)
        else { return }
        if
            let said = game.dialogue.commentOnPlayer(
                line,
                witnesses: frame.speakers,
                now: frame.now
            )
        {
            sayAmbient(said)
        }
    }

    /// `speaker` says its line of `line`'s subtype now, if its wait allows.
    public func sayOwnLine(_ line: NPCSpeechLine, speaker: ReferenceKey) {
        guard let info = game.dialogue.npcLine(line, speaker: speaker, now: sceneCast.sceneSeconds)
        else {
            return
        }
        sayAmbient(AmbientLine(info: info, speaker: speaker, kind: line))
    }

    /// `speaker` says the first line of `subtype` its conditions allow, recorded as said.
    /// - Returns: the line's seconds, or nil when it had none to say.
    @discardableResult
    public func sayTopic(
        _ subtype: FourCC,
        speaker: ReferenceKey,
        lookAt: ReferenceKey?
    ) -> Float? {
        guard
            let runtime = game.dialogue.runtime,
            let offer = runtime.topics(subtype: subtype, speaker: speaker).offers.first,
            attempt({ try runtime.choose(offer.info, speaker: speaker) }) != nil,
            let info = runtime.dialogue.info(offer.info)
        else { return nil }
        let seconds = sceneLines.lineDuration(of: info, speaker: speaker) ?? SceneLine
            .defaultSeconds
        sceneLines.speak(info: offer.info, speaker: speaker, lookAt: lookAt, seconds: seconds)
        return seconds
    }

    private func sayAmbient(_ line: AmbientLine) {
        guard let info = game.dialogue.runtime?.dialogue.info(line.info) else { return }
        let seconds = sceneLines.lineDuration(of: info, speaker: line.speaker) ?? SceneLine
            .defaultSeconds
        let lookAt: ReferenceKey? = line.kind == .combatTaunt ? nil : .player
        sceneLines.speak(info: line.info, speaker: line.speaker, lookAt: lookAt, seconds: seconds)
    }

    private func ambientSpeechFrame(now: Double) -> AmbientSpeechFrame? {
        guard let player = game.gameSession?.walkController.feetPosition else { return nil }
        let inScenes = game.scenes.actorsInScenes()
        let conversation = game.dialogue.conversationSpeaker
        let perception = game.perception.runtime
        let loop = game.combat.loop
        let speakers = game.actorWorld.combatActors().map { actor in
            let flags = game.packages.runtime?.currentPackage(for: actor.key)?
                .package.general.interruptFlags ?? 0
            let state = perception?.state(observer: actor.key, target: .player).state
            return AmbientSpeaker(
                key: actor.key,
                distanceToPlayer: simd_distance(actor.feet, player),
                seesPlayer: state == .detected,
                isFighting: loop?.phase(of: actor.key)?.isEngaged ?? false,
                isFree: !actor.isDead && !inScenes.contains(actor.key) && actor.key != conversation,
                allowsHello: flags & 0x01 != 0
            )
        }
        return AmbientSpeechFrame(
            speakers: speakers, now: now, playerInConversation: conversation != nil
        )
    }

    // The author named these idles, so they play without their own conditions.
}

/// A line waiting out `fSpeechDelay` before it starts.
public struct DelayedLine {
    public let due: Double
    public let info: FormID
    public let speaker: ReferenceKey
    public let lookAt: ReferenceKey?
    public let seconds: Float
}
