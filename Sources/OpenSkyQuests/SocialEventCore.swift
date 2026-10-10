// Which story events NPCs send to each other: `ADIA` (a random conversation),
// `AHEL` (a hello in passing), and `DEAD` (an actor finds a body). Values in,
// values out; the coordinator fires them. Rules: docs/engine/random-conversations.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// One loaded actor as the social pass sees it.
nonisolated public struct SocialActor: Equatable, Sendable {
    public let key: ReferenceKey
    public let feet: SIMD3<Float>
    /// The interrupt flags (`PKDT`) of the package it runs. Nil: no package.
    public let interruptFlags: UInt16?
    public let isDead: Bool
    public let isInScene: Bool

    public init(
        key: ReferenceKey, feet: SIMD3<Float>, interruptFlags: UInt16?,
        isDead: Bool = false, isInScene: Bool = false
    ) {
        self.key = key
        self.feet = feet
        self.interruptFlags = interruptFlags
        self.isDead = isDead
        self.isInScene = isInScene
    }

    /// `PKDT` interrupt flag 0x02: the package allows random conversations.
    public var allowsRandomConversation: Bool {
        (interruptFlags ?? 0) & 0x02 != 0
    }

    /// `PKDT` interrupt flag 0x08: greet corpse behaviour.
    public var greetsCorpses: Bool {
        (interruptFlags ?? 0) & 0x08 != 0
    }

    var isFree: Bool {
        !isDead && !isInScene && key != .player
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

    public init(actors: [SocialActor], now: Double, isInterior: Bool, playerInConversation: Bool) {
        self.actors = actors
        self.now = now
        self.isInterior = isInterior
        self.playerInConversation = playerInConversation
    }
}

/// An unordered pair of actors.
nonisolated struct SocialPair: Hashable, Sendable {
    let first: ReferenceKey
    let second: ReferenceKey

    init(_ one: ReferenceKey, _ other: ReferenceKey) {
        if one < other {
            first = one
            second = other
        } else {
            first = other
            second = one
        }
    }
}

/// What the social pass remembers between calls. Not saved: a loaded game rolls
/// its timers again.
nonisolated public struct SocialState: Sendable {
    var nextAttempt: [ReferenceKey: Double] = [:]
    var lastPosition: [ReferenceKey: SIMD3<Float>] = [:]
    var lastTalk: [SocialPair: Double] = [:]
    var lastHello: [SocialPair: Double] = [:]
    /// Observer and body pairs that already sent `DEAD`.
    var foundBodies: Set<FoundBody> = []
    var random = SplitMix64(seed: 0x50C1A1)

    public init() {}

    nonisolated struct FoundBody: Hashable, Sendable {
        let observer: ReferenceKey
        let body: ReferenceKey
    }
}

nonisolated public enum SocialEventCore {
    /// Game units an actor must move between passes to count as moving.
    static let movingDistance: Float = 8

    /// The events this pass sends, in actor order. `canSee` tests a sight line.
    public static func events(
        _ frame: SocialFrame,
        settings: SocialSettings,
        state: inout SocialState,
        canSee: (SocialActor, SocialActor) -> Bool
    ) -> [StoryEventData] {
        let actors = frame.actors.sorted { $0.key < $1.key }
        var moving: Set<ReferenceKey> = []
        for actor in actors {
            if
                let last = state.lastPosition[actor.key],
                simd_distance(last, actor.feet) >= movingDistance
            {
                moving.insert(actor.key)
            }
            state.lastPosition[actor.key] = actor.feet
        }
        let radius = frame.isInterior ? settings.interiorRadius : settings.radius
        var events = bodies(actors, radius: radius, state: &state, canSee: canSee)
        guard !frame.playerInConversation else { return events }
        events += hellos(actors, moving: moving, frame: frame, settings: settings, state: &state)
        events += conversations(actors, frame: frame, settings: settings, state: &state)
        return events
    }

    /// `DEAD`: a free actor whose package greets corpses sees a body it has not found
    /// yet, within the social radius. The radius is OpenSky's choice; no GMST names one.
    static func bodies(
        _ actors: [SocialActor],
        radius: Float,
        state: inout SocialState,
        canSee: (SocialActor, SocialActor) -> Bool
    ) -> [StoryEventData] {
        let bodies = actors.filter(\.isDead)
        guard !bodies.isEmpty else { return [] }
        var events: [StoryEventData] = []
        for observer in actors where observer.isFree && observer.greetsCorpses {
            for body in bodies {
                let pair = SocialState.FoundBody(observer: observer.key, body: body.key)
                guard
                    !state.foundBodies.contains(pair),
                    simd_distance(observer.feet, body.feet) <= radius,
                    canSee(observer, body)
                else { continue }
                state.foundBodies.insert(pair)
                events.append(event("DEAD", observer.key, body.key))
            }
        }
        return events
    }

    /// `AHEL`: a moving actor passes a standing actor within the trigger distance.
    static func hellos(
        _ actors: [SocialActor],
        moving: Set<ReferenceKey>,
        frame: SocialFrame,
        settings: SocialSettings,
        state: inout SocialState
    ) -> [StoryEventData] {
        var events: [StoryEventData] = []
        for walker in actors
            where walker.isFree && walker.allowsRandomConversation && moving.contains(walker.key)
        {
            let target = actors.first { other in
                other.key != walker.key && other.isFree && !moving.contains(other.key)
                    && simd_distance(other.feet, walker.feet) <= settings.triggerDistance
                    && frame.now - (state.lastHello[SocialPair(walker.key, other.key)]
                        ?? -.infinity) >= Double(settings.sameActorSeconds)
            }
            guard let target else { continue }
            state.lastHello[SocialPair(walker.key, target.key)] = frame.now
            events.append(event("AHEL", walker.key, target.key))
        }
        return events
    }

    /// `ADIA`: on its timer, an actor rolls the social chance and talks to a valid
    /// target within the trigger distance.
    static func conversations(
        _ actors: [SocialActor],
        frame: SocialFrame,
        settings: SocialSettings,
        state: inout SocialState
    ) -> [StoryEventData] {
        let radius = frame.isInterior ? settings.interiorRadius : settings.radius
        let chance = frame.isInterior ? settings.interiorChance : settings.chance
        var talking: Set<ReferenceKey> = []
        var events: [StoryEventData] = []
        for speaker in actors where speaker.isFree && speaker.allowsRandomConversation {
            guard let due = state.nextAttempt[speaker.key] else {
                state.nextAttempt[speaker.key] = frame.now + rollTimer(settings, &state.random)
                continue
            }
            guard due <= frame.now, !talking.contains(speaker.key) else { continue }
            state.nextAttempt[speaker.key] = frame.now + rollTimer(settings, &state.random)
            let targets = actors.filter { other in
                other.key != speaker.key && other.isFree && other.allowsRandomConversation
                    && !talking.contains(other.key)
                    && simd_distance(other.feet, speaker.feet) <= radius
                    && frame.now - (state.lastTalk[SocialPair(speaker.key, other.key)]
                        ?? -.infinity) >= Double(settings.sameActorSeconds)
            }
            guard
                !targets.isEmpty,
                Float(state.random.next() % 10000) / 100 < chance
            else { continue }
            let nearest = targets.min {
                simd_distance($0.feet, speaker.feet) < simd_distance($1.feet, speaker.feet)
            }
            guard
                let target = nearest,
                simd_distance(target.feet, speaker.feet) <= settings.triggerDistance
            else { continue }
            state.lastTalk[SocialPair(speaker.key, target.key)] = frame.now
            talking.formUnion([speaker.key, target.key])
            events.append(event("ADIA", speaker.key, target.key))
        }
        return events
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
