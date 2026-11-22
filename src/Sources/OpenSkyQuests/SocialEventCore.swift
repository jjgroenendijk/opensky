// What NPCs do with each other: random conversations (`ADIA`) and the walk to the
// partner, hellos in passing (`AHEL`), watching a fight, and finding a body (`DEAD`).
// Values in, values out; the coordinator runs the commands. Rules:
// docs/engine/random-conversations.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyQuestsInterface
import simd

/// One loaded actor as the social pass sees it.
nonisolated public struct SocialActor: Equatable, Sendable {
    public let key: ReferenceKey
    public let feet: SIMD3<Float>
    /// The interrupt flags (`PKDT`) of the package it runs. Nil: no package.
    public let interruptFlags: UInt16?
    public let isDead: Bool
    public let isInScene: Bool
    public let isInCombat: Bool
    public let combatTarget: ReferenceKey?
    /// The body's heading in radians, 0 along +Y and growing toward +X.
    public var heading: Float = 0
    public var posture: SocialPosture = .standing
    /// It fights with a bow, a crossbow, a staff, or a spell.
    public var fightsRanged = false
    /// Its race has the size Extra Large, so it looks at actors from further away.
    public var isLargeCreature = false

    public init(
        key: ReferenceKey, feet: SIMD3<Float>, interruptFlags: UInt16?,
        isDead: Bool = false, isInScene: Bool = false, isInCombat: Bool = false,
        combatTarget: ReferenceKey? = nil
    ) {
        self.key = key
        self.feet = feet
        self.interruptFlags = interruptFlags
        self.isDead = isDead
        self.isInScene = isInScene
        self.isInCombat = isInCombat
        self.combatTarget = combatTarget
    }

    /// `PKDT` interrupt flag 0x02: random conversations and hellos in passing.
    public static let conversationFlag: UInt16 = 0x02

    var allowsConversation: Bool {
        (interruptFlags ?? 0) & Self.conversationFlag != 0
    }

    /// `PKDT` interrupt flag 0x04: observe combat behaviour.
    var observesCombat: Bool {
        (interruptFlags ?? 0) & 0x04 != 0
    }

    /// `PKDT` interrupt flag 0x08: greet corpse behaviour.
    var greetsCorpses: Bool {
        (interruptFlags ?? 0) & 0x08 != 0
    }

    /// Alive, not the player, not in a scene, and not fighting.
    var isFree: Bool {
        !isDead && !isInScene && !isInCombat && combatTarget == nil && key != .player
    }
}

nonisolated public enum SocialPosture: Equatable, Sendable {
    case standing, sitting, sleeping
}

/// The world facts of one social pass.
nonisolated public struct SocialFrame: Sendable {
    public var actors: [SocialActor]
    /// Real seconds since the session started.
    public var now: Double
    public var isInterior: Bool
    /// The player is in the dialogue menu, which the CK counts as an important conversation.
    public var playerInConversation: Bool
    /// The player's feet. Nil: no player, and no actor is near enough to talk.
    public var player: SIMD3<Float>?

    public init(
        actors: [SocialActor], now: Double, isInterior: Bool, playerInConversation: Bool,
        player: SIMD3<Float>?
    ) {
        self.actors = actors
        self.now = now
        self.isInterior = isInterior
        self.playerInConversation = playerInConversation
        self.player = player
    }
}

nonisolated public enum SocialEventCore {
    /// The commands this pass sends, in a fixed order: bodies, watchers, hellos,
    /// conversations, then the conversations already running.
    public static func pass(
        _ frame: SocialFrame,
        settings: SocialSettings,
        state: inout SocialState,
        canSee: (SocialActor, SocialActor) -> Bool
    ) -> [SocialEventCommand] {
        var frame = frame
        frame.actors.sort { $0.key < $1.key }
        let elapsed = state.lastPass.map { max(0, frame.now - $0) } ?? 0
        state.lastPass = frame.now
        let reacts = frame.now >= state.nextReaction
        if reacts {
            state.nextReaction = frame.now + SocialLimits.reactionSeconds
        }
        var commands: [SocialEventCommand] = []
        if reacts {
            commands += bodies(frame, settings: settings, state: &state, canSee: canSee)
        }
        commands += finders(frame, state: &state)
        commands += spectators(
            frame, timing: WatchTiming(settings: settings, elapsed: elapsed, reacts: reacts),
            state: &state, canSee: canSee
        )
        if !frame.playerInConversation {
            commands += hellos(frame, state: &state, canSee: canSee)
            commands += conversations(frame, settings: settings, elapsed: elapsed, state: &state)
        }
        commands += progress(frame, settings: settings, state: &state, canSee: canSee)
        return commands
    }

    /// The default look target of each free actor near the player, checked every 1.0 to
    /// 1.5 s and held 5 s. A walker with flag 0x02 whose new target is an NPC sends `AHEL`.
    static func hellos(
        _ frame: SocialFrame, state: inout SocialState,
        canSee: (SocialActor, SocialActor) -> Bool
    ) -> [SocialEventCommand] {
        guard let playerFeet = frame.player else { return [] }
        let player = SocialActor(key: .player, feet: playerFeet, interruptFlags: nil)
        var commands: [SocialEventCommand] = []
        var checks = 0
        for looker in frame.actors where looker.isFree {
            guard
                checks < SocialLimits.lookChecksPerPass,
                simd_distance(looker.feet, playerFeet) <= (looker.isLargeCreature
                    ? SocialLimits.largeCreatureLookDistance : SocialLimits.lookPlayerDistance)
            else { continue }
            let last = state.looks[looker.key]
            guard frame.now >= (last?.nextCheck ?? -.infinity) else { continue }
            checks += 1
            let span = SocialLimits.lookCheckSeconds
            let unit = Double(state.random.next() % 1000) / 1000
            var look = SocialLook(
                nextCheck: frame.now + span.lowerBound + (span.upperBound - span.lowerBound) * unit,
                feet: looker.feet, checkedAt: frame.now
            )
            look.target = last?.target
            look.heldUntil = last?.heldUntil ?? -.infinity
            defer { state.looks[looker.key] = look }
            guard !state.isBusy(looker.key) else {
                look.target = nil
                continue
            }
            guard frame.now >= look.heldUntil else { continue }
            let old = look.target
            let candidates = [player] + frame.actors
            let target = candidates.first {
                isLookTarget($0, of: looker, old: old) && canSee(looker, $0)
            }
            look.target = target?.key
            guard let target else { continue }
            look.heldUntil = frame.now + SocialLimits.lookHoldSeconds
            guard target.key != .player else { continue }
            commands.append(.look(looker.key, at: target.key))
            let walks = last.map {
                isMoving(from: $0.feet, at: $0.checkedAt, to: looker.feet, now: frame.now)
            } ?? false
            if target.key != old, walks, looker.allowsConversation, !target.isInScene {
                commands.append(.reportStoryEvent(event("AHEL", looker.key, target.key)))
            }
        }
        return commands
    }

    /// The rules of docs/engine/head-tracking.md#the-default-target, without detection.
    static func isLookTarget(
        _ target: SocialActor, of looker: SocialActor, old: ReferenceKey?
    ) -> Bool {
        guard target.key != looker.key, !target.isDead else { return false }
        let offset = target.feet - looker.feet
        let distance = simd_length(offset)
        let reach = looker.isLargeCreature
            ? SocialLimits.largeCreatureLookDistance : SocialLimits.lookDistance
        guard distance <= reach else { return false }
        if target.key != .player, distance < SocialLimits.lookNearDistance {
            return false
        }
        if looker.posture != .standing, target.posture != .standing {
            return false
        }
        guard target.key != old else { return true }
        let turn = (atan2(offset.x, offset.y) - looker.heading).remainder(dividingBy: 2 * .pi)
        return abs(turn) <= SocialLimits.lookHalfAngle
    }

    static func isMoving(
        from old: SIMD3<Float>, at then: Double, to feet: SIMD3<Float>, now: Double
    ) -> Bool {
        let seconds = Float(now - then)
        return seconds > 0 && simd_distance(old, feet) / seconds >= SocialLimits.movingSpeed
    }

    static func rollTimer(_ settings: SocialSettings, _ random: inout SplitMix64) -> Double {
        let span = Double(settings.timerMax - settings.timerMin)
        let unit = Double(random.next() % 1_000_000) / 1_000_000
        return Double(settings.timerMin) + span * unit
    }

    static func event(_ code: FourCC, _ first: ReferenceKey, _ second: ReferenceKey)
        -> StoryEventData
    {
        var event = StoryEventData(event: code)
        event.actor1 = first
        event.actor2 = second
        return event
    }
}
