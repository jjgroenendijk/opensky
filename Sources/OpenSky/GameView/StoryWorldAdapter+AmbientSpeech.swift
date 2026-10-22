// App side of the lines NPCs say on their own: the delayed line queue, the ambient pass
// (hellos, idle chatter, taunts), and comments on the player. The rules live in
// `DialogueCoordinator+Speech` (docs/engine/dialogue.md#speech-timers).

import OpenSkyAIPackages
import OpenSkyCombat
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyWorld
import simd

/// A line waiting out `fSpeechDelay` before it starts.
struct DelayedLine {
    let due: Double
    let info: FormID
    let speaker: ReferenceKey
    let lookAt: ReferenceKey?
    let seconds: Float
}

extension StoryWorldAdapter {
    /// Frames between ambient speech passes, so each pass reads the actors a few times
    /// a second rather than every frame.
    static let ambientSpeechInterval = 15

    /// Starts the lines whose delay has passed, then runs the ambient pass on its interval.
    func tickAmbientSpeech() {
        let now = sceneSeconds
        let due = delayedLines.filter { $0.due <= now }
        delayedLines.removeAll { $0.due <= now }
        for line in due {
            startLine(
                info: line.info,
                speaker: line.speaker,
                lookAt: line.lookAt,
                seconds: line.seconds
            )
        }
        if game.streamer?.dynamicBodies.lastPushCount ?? 0 > 0 {
            commentOnPlayer(.knockOver)
        }
        framesSinceAmbientSpeech += 1
        guard framesSinceAmbientSpeech >= Self.ambientSpeechInterval else { return }
        framesSinceAmbientSpeech = 0
        let elapsed = Float(now - (lastAmbientSpeechSeconds ?? now))
        lastAmbientSpeechSeconds = now
        guard let frame = ambientSpeechFrame(now: now) else { return }
        for line in game.dialogue.ambientLines(frame, seconds: elapsed) {
            sayAmbient(line)
        }
    }

    /// A witness near the player comments on `line`, such as a shout or a bow shot.
    func commentOnPlayer(_ line: NPCSpeechLine) {
        guard
            game.dialogue.isSharedReady(line, now: sceneSeconds),
            let frame = ambientSpeechFrame(now: sceneSeconds)
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
    func sayOwnLine(_ line: NPCSpeechLine, speaker: ReferenceKey) {
        guard let info = game.dialogue.npcLine(line, speaker: speaker, now: sceneSeconds) else {
            return
        }
        sayAmbient(AmbientLine(info: info, speaker: speaker, kind: line))
    }

    /// `speaker` says the first line of `subtype` its conditions allow, recorded as said.
    /// - Returns: the line's seconds, or nil when it had none to say.
    @discardableResult
    func sayTopic(_ subtype: FourCC, speaker: ReferenceKey, lookAt: ReferenceKey?) -> Float? {
        guard
            let runtime = game.dialogue.runtime,
            let offer = runtime.topics(subtype: subtype, speaker: speaker).offers.first,
            (try? runtime.choose(offer.info, speaker: speaker)) != nil,
            let info = runtime.dialogue.info(offer.info)
        else { return nil }
        let seconds = lineDuration(of: info, speaker: speaker) ?? SceneLine.defaultSeconds
        speak(info: offer.info, speaker: speaker, lookAt: lookAt, seconds: seconds)
        return seconds
    }

    private func sayAmbient(_ line: AmbientLine) {
        guard let info = game.dialogue.runtime?.dialogue.info(line.info) else { return }
        let seconds = lineDuration(of: info, speaker: line.speaker) ?? SceneLine.defaultSeconds
        let lookAt: ReferenceKey? = line.kind == .combatTaunt ? nil : .player
        speak(info: line.info, speaker: line.speaker, lookAt: lookAt, seconds: seconds)
    }

    private func ambientSpeechFrame(now: Double) -> AmbientSpeechFrame? {
        guard
            game.streamer != nil,
            let player = game.gameSession?.walkController.feetPosition
        else { return nil }
        let inScenes = scenes.actorsInScenes()
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
}
