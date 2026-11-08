import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyDialogue
public import OpenSkyDialogueInterface
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import simd

/// What `StoryAmbientTalkAdapter` reads from the session.
@MainActor
public protocol StoryAmbientTalkHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var dialogue: any DialoguePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var idles: any IdlePort { get }
    var packages: any PackagePort { get }
    var perception: any PerceptionPort { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `StoryWorldAdapter`, over its own narrow host.
public struct StoryAmbientTalkAdapter {
    public unowned let owner: StoryWorldAdapter
    public unowned let game: any StoryAmbientTalkHost
}

extension StoryAmbientTalkAdapter {
    /// Frames between ambient speech passes, so each pass reads the actors a few times
    /// a second rather than every frame.
    public static let ambientSpeechInterval = 15

    /// Starts the lines whose delay has passed, then runs the ambient pass on its interval.
    public func tickAmbientSpeech() {
        let now = owner.sceneSeconds
        let due = owner.delayedLines.filter { $0.due <= now }
        owner.delayedLines.removeAll { $0.due <= now }
        for line in due {
            owner.sceneLines.startLine(
                info: line.info,
                speaker: line.speaker,
                lookAt: line.lookAt,
                seconds: line.seconds
            )
        }
        if game.streamer?.dynamicBodies.lastPushCount ?? 0 > 0 {
            commentOnPlayer(.knockOver)
        }
        owner.framesSinceAmbientSpeech += 1
        guard owner.framesSinceAmbientSpeech >= Self.ambientSpeechInterval else { return }
        owner.framesSinceAmbientSpeech = 0
        let elapsed = Float(now - (owner.lastAmbientSpeechSeconds ?? now))
        owner.lastAmbientSpeechSeconds = now
        guard let frame = ambientSpeechFrame(now: now) else { return }
        for line in game.dialogue.ambientLines(frame, seconds: elapsed) {
            sayAmbient(line)
        }
    }

    /// A witness near the player comments on `line`, such as a shout or a bow shot.
    public func commentOnPlayer(_ line: NPCSpeechLine) {
        guard
            game.dialogue.isSharedReady(line, now: owner.sceneSeconds),
            let frame = ambientSpeechFrame(now: owner.sceneSeconds)
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
        guard let info = game.dialogue.npcLine(line, speaker: speaker, now: owner.sceneSeconds)
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
            (try? runtime.choose(offer.info, speaker: speaker)) != nil,
            let info = runtime.dialogue.info(offer.info)
        else { return nil }
        let seconds = owner.lineDuration(of: info, speaker: speaker) ?? SceneLine.defaultSeconds
        owner.speak(info: offer.info, speaker: speaker, lookAt: lookAt, seconds: seconds)
        return seconds
    }

    private func sayAmbient(_ line: AmbientLine) {
        guard let info = game.dialogue.runtime?.dialogue.info(line.info) else { return }
        let seconds = owner.lineDuration(of: info, speaker: line.speaker) ?? SceneLine
            .defaultSeconds
        let lookAt: ReferenceKey? = line.kind == .combatTaunt ? nil : .player
        owner.speak(info: line.info, speaker: line.speaker, lookAt: lookAt, seconds: seconds)
    }

    private func ambientSpeechFrame(now: Double) -> AmbientSpeechFrame? {
        guard
            game.streamer != nil,
            let player = game.gameSession?.walkController.feetPosition
        else { return nil }
        let inScenes = owner.scenes.actorsInScenes()
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

    /// The author named these idles, so they play without their own conditions.
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

/// A line waiting out `fSpeechDelay` before it starts.
public struct DelayedLine {
    public let due: Double
    public let info: FormID
    public let speaker: ReferenceKey
    public let lookAt: ReferenceKey?
    public let seconds: Float
}
