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
        let moving = movingActors(frame.actors, state: &state)
        var commands = bodies(frame, settings: settings, state: &state, canSee: canSee)
        commands += spectators(frame, settings: settings, state: &state, canSee: canSee)
        if !frame.playerInConversation {
            commands += hellos(frame.actors, moving: moving, state: &state)
            commands += conversations(frame, settings: settings, elapsed: elapsed, state: &state)
        }
        commands += progress(frame, settings: settings, state: &state, canSee: canSee)
        return commands
    }

    static func movingActors(
        _ actors: [SocialActor],
        state: inout SocialState
    ) -> Set<ReferenceKey> {
        var moving: Set<ReferenceKey> = []
        for actor in actors {
            if
                let last = state.lastPosition[actor.key],
                simd_distance(last, actor.feet) >= SocialLimits.movingDistance
            {
                moving.insert(actor.key)
            }
            state.lastPosition[actor.key] = actor.feet
        }
        return moving
    }

    /// `AHEL`: a walker with flag 0x02 looks at the nearest other free NPC, and a new
    /// look target sends the event. A walker that stops forgets its target.
    static func hellos(
        _ actors: [SocialActor], moving: Set<ReferenceKey>, state: inout SocialState
    ) -> [SocialEventCommand] {
        var commands: [SocialEventCommand] = []
        for walker in actors where walker.isFree && walker.allowsConversation {
            guard moving.contains(walker.key), !state.isBusy(walker.key) else {
                state.lookTargets[walker.key] = nil
                continue
            }
            let target = actors.filter { other in
                other.key != walker.key && other.isFree
                    && simd_distance(other.feet, walker.feet) <= SocialLimits.lookDistance
            }.min { simd_distance($0.feet, walker.feet) < simd_distance($1.feet, walker.feet) }
            guard let target, state.lookTargets[walker.key] != target.key else { continue }
            state.lookTargets[walker.key] = target.key
            commands.append(.look(walker.key, at: target.key))
            commands.append(.reportStoryEvent(event("AHEL", walker.key, target.key)))
        }
        return commands
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
