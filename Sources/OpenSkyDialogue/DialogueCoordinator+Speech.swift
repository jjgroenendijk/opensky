// Lines an NPC says on its own: a force greet, hellos, combat lines and taunts, idle
// chatter, and comments on the player, each held back by its `SpeechTimerSettings` wait.
// See docs/engine/dialogue.md#speech-timers.

import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM

extension DialogueCoordinator {
    /// True when `speaker` may force greet now, which starts its `fAIForceGreetingTimer`.
    public func claimForceGreet(speaker: ReferenceKey, now: Double) -> Bool {
        guard speechClock.isReady(.forceGreeting, speaker: speaker, now: now) else {
            return false
        }
        speechClock.note(
            .forceGreeting, speaker: speaker, now: now,
            wait: speechTimers.wait(after: .forceGreeting, unit: 0)
        )
        return true
    }

    /// The combat line `speaker` says now, recorded as said, or nil when its window has
    /// not passed, the chance roll fails, or no topic of the line's subtype passes.
    public func combatLine(
        _ line: NPCSpeechLine, speaker: ReferenceKey, now: Double
    ) -> FormID? {
        guard Float(speechRandom.percent()) < speechTimers.chance(of: line) * 100 else {
            return nil
        }
        return npcLine(line, speaker: speaker, now: now)
    }

    /// The line of `line`'s subtype `speaker` says now, recorded as said with its own
    /// and its shared wait, or nil when a wait holds it or no topic passes.
    public func npcLine(_ line: NPCSpeechLine, speaker: ReferenceKey, now: Double) -> FormID? {
        guard
            let subtype = line.subtype,
            speechClock.isReady(line, speaker: speaker, now: now),
            let selection = runtime?.topics(subtype: subtype, speaker: speaker),
            let info = sayAlone(selection, speaker: speaker)
        else { return nil }
        let unit = Float(speechRandom.percent()) / 99
        speechClock.note(
            line, speaker: speaker, now: now,
            wait: speechTimers.wait(after: line, unit: unit),
            sharedWait: speechTimers.sharedWait(after: line, unit: unit)
        )
        return info
    }

    /// The lines NPCs say on their own this pass: one hello, one idle comment, and the
    /// taunts of the fighters. `seconds` is the time since the last pass.
    public func ambientLines(_ frame: AmbientSpeechFrame, seconds: Float) -> [AmbientLine] {
        var lines: [AmbientLine] = []
        if !frame.playerInConversation {
            lines += hello(frame)
            lines += idleChatter(frame)
        }
        let tauntChance = speechTimers.tauntChance(over: seconds) * 100
        for speaker in frame.speakers where speaker.isFighting && speaker.isFree {
            guard
                speechClock.isReady(.combatTaunt, speaker: speaker.key, now: frame.now),
                Float(speechRandom.percent()) < tauntChance,
                let info = npcLine(.combatTaunt, speaker: speaker.key, now: frame.now)
            else { continue }
            lines.append(AmbientLine(info: info, speaker: speaker.key, kind: .combatTaunt))
        }
        return lines
    }

    /// Whether the shared wait of `line` has passed, so a caller can skip building a frame.
    public func isSharedReady(_ line: NPCSpeechLine, now: Double) -> Bool {
        speechClock.isSharedReady(line, now: now)
    }

    /// A witness comments on what the player just did: the nearest one that sees it.
    public func commentOnPlayer(
        _ line: NPCSpeechLine, witnesses: [AmbientSpeaker], now: Double
    ) -> AmbientLine? {
        guard speechClock.isSharedReady(line, now: now) else { return nil }
        let candidates = witnesses
            .filter { $0.isFree && !$0.isFighting && $0.seesPlayer }
            .filter { $0.distanceToPlayer <= AmbientSpeechFrame.commentDistance }
            .sorted { $0.distanceToPlayer < $1.distanceToPlayer }
        for witness in candidates {
            if let info = npcLine(line, speaker: witness.key, now: now) {
                return AmbientLine(info: info, speaker: witness.key, kind: line)
            }
        }
        return nil
    }

    /// The nearest free NPC that sees the player inside the greeting distance says hello.
    private func hello(_ frame: AmbientSpeechFrame) -> [AmbientLine] {
        guard speechClock.isSharedReady(.hello, now: frame.now) else { return [] }
        let candidates = frame.speakers
            .filter { $0.isFree && !$0.isFighting && $0.seesPlayer && $0.allowsHello }
            .filter { $0.distanceToPlayer <= speechTimers.greetingDistance }
            .sorted { $0.distanceToPlayer < $1.distanceToPlayer }
        for speaker in candidates {
            if let info = npcLine(.hello, speaker: speaker.key, now: frame.now) {
                return [AmbientLine(info: info, speaker: speaker.key, kind: .hello)]
            }
        }
        return []
    }

    /// One free NPC near the player says an idle line once the shared wait has passed.
    /// The order is seeded, so the same NPC does not always speak first.
    private func idleChatter(_ frame: AmbientSpeechFrame) -> [AmbientLine] {
        guard speechClock.isSharedReady(.idleChatter, now: frame.now) else { return [] }
        let candidates = frame.speakers
            .filter { $0.isFree && !$0.isFighting }
            .filter { $0.distanceToPlayer <= AmbientSpeechFrame.idleChatterDistance }
        guard !candidates.isEmpty else { return [] }
        // One speaker a pass: a line search runs every IDLE topic's conditions, so a
        // crowd that searched all at once stalled the frame.
        let speaker = candidates[Int(speechRandom.percent()) % candidates.count]
        guard let info = npcLine(.idleChatter, speaker: speaker.key, now: frame.now) else {
            return []
        }
        return [AmbientLine(info: info, speaker: speaker.key, kind: .idleChatter)]
    }
}

/// One NPC as the ambient speech pass sees it.
nonisolated public struct AmbientSpeaker: Equatable, Sendable {
    public let key: ReferenceKey
    public let distanceToPlayer: Float
    /// Whether it detects the player.
    public let seesPlayer: Bool
    /// Engaged in a fight.
    public let isFighting: Bool
    /// Alive, not in a scene, and not in the player's conversation.
    public let isFree: Bool
    /// Its package allows hellos to the player (`PKDT` interrupt flag 0x01).
    public let allowsHello: Bool

    public init(
        key: ReferenceKey, distanceToPlayer: Float, seesPlayer: Bool, isFighting: Bool,
        isFree: Bool, allowsHello: Bool
    ) {
        self.key = key
        self.distanceToPlayer = distanceToPlayer
        self.seesPlayer = seesPlayer
        self.isFighting = isFighting
        self.isFree = isFree
        self.allowsHello = allowsHello
    }
}

/// The loaded NPCs for one ambient speech pass.
nonisolated public struct AmbientSpeechFrame: Equatable, Sendable {
    /// OpenSky's: no setting names how near an idle comment must be to be said.
    public static let idleChatterDistance: Float = 1000
    /// OpenSky's: how near a witness must be to comment on the player.
    public static let commentDistance: Float = 1000

    public let speakers: [AmbientSpeaker]
    public let now: Double
    public let playerInConversation: Bool

    public init(speakers: [AmbientSpeaker], now: Double, playerInConversation: Bool) {
        self.speakers = speakers
        self.now = now
        self.playerInConversation = playerInConversation
    }
}

/// A line the ambient speech pass chose.
nonisolated public struct AmbientLine: Equatable, Sendable {
    public let info: FormID
    public let speaker: ReferenceKey
    public let kind: NPCSpeechLine

    public init(info: FormID, speaker: ReferenceKey, kind: NPCSpeechLine) {
        self.info = info
        self.speaker = speaker
        self.kind = kind
    }
}
