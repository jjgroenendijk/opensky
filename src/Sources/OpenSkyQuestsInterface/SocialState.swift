// What the social pass keeps between passes. A save keeps it, so a loaded game
// goes on with the same timers, pairs, and bodies
// (docs/engine/random-conversations.md#what-a-save-keeps).

import Foundation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM

/// One random conversation, from its `ADIA` to its end.
nonisolated public struct SocialConversation: Equatable, Sendable {
    nonisolated public enum Phase: UInt8, Equatable, Sendable {
        /// `ADIA` fired; the next pass sees whether a quest answered with a scene.
        case waitingForAnswer = 0
        /// The speaker walks to the partner, who waits. The scene is paused.
        case approaching = 1
        /// Both face each other and the scene plays.
        case talking = 2
    }

    public let speaker: ReferenceKey
    public let partner: ReferenceKey
    /// When `ADIA` fired.
    public let startedAt: Double
    /// How long the pair waits for a quest to answer.
    public let answerSeconds: Double
    /// A package asked for it, so it waits its whole time for a quest.
    public let isPackageRequest: Bool
    public var phase: Phase
    /// Where the speaker walks; nil before the first walk.
    public var goal: SIMD3<Float>?

    public init(
        speaker: ReferenceKey, partner: ReferenceKey, startedAt: Double,
        answerSeconds: Double = SocialLimits.answerSeconds,
        isPackageRequest: Bool = false,
        phase: Phase = .waitingForAnswer, goal: SIMD3<Float>? = nil
    ) {
        self.speaker = speaker
        self.partner = partner
        self.startedAt = startedAt
        self.answerSeconds = answerSeconds
        self.isPackageRequest = isPackageRequest
        self.phase = phase
        self.goal = goal
    }
}

/// One attacker a watcher knows, with the actor it fights.
nonisolated public struct SocialThreat: Equatable, Sendable {
    public let attacker: ReferenceKey
    public var target: ReferenceKey?
    /// The last time the watcher detected the attacker fighting.
    public var lastSeen: Double

    public init(attacker: ReferenceKey, target: ReferenceKey?, lastSeen: Double) {
        self.attacker = attacker
        self.target = target
        self.lastSeen = lastSeen
    }
}

/// One actor watching a fight.
nonisolated public struct SocialSpectator: Equatable, Sendable {
    public var threats: [SocialThreat]
    /// Seconds before the next comment roll. It starts at 0.
    public var commentTimer: Double
    /// The time and place of the last back-off step.
    public var lastStep: Double
    public var lastStepFeet: SIMD3<Float>?
    /// Where the watcher backs off to, while it walks there.
    public var backOffGoal: SIMD3<Float>?
    /// Set after a back-off: the watcher's body faces the fight's centre.
    public var facesCentre: Bool
    /// A watcher in a scene keeps its scene's package; the scene's flags decide.
    public let inScene: Bool

    public init(threats: [SocialThreat], startedAt: Double, inScene: Bool = false) {
        self.threats = threats
        commentTimer = 0
        lastStep = startedAt
        facesCentre = false
        self.inScene = inScene
    }
}

/// One actor walking to a body it found.
nonisolated public struct SocialFinder: Equatable, Sendable {
    public let body: ReferenceKey
    public let startedAt: Double

    public init(body: ReferenceKey, startedAt: Double) {
        self.body = body
        self.startedAt = startedAt
    }
}

/// What one actor's default look check keeps. Not saved.
nonisolated public struct SocialLook: Equatable, Sendable {
    public var target: ReferenceKey?
    /// The next check, and the end of the hold on the target.
    public var nextCheck: Double
    public var heldUntil: Double
    /// Where the actor stood at the last check, and when.
    public var feet: SIMD3<Float>
    public var checkedAt: Double

    public init(nextCheck: Double, feet: SIMD3<Float>, checkedAt: Double) {
        self.nextCheck = nextCheck
        heldUntil = -.infinity
        self.feet = feet
        self.checkedAt = checkedAt
    }
}

nonisolated public struct SocialState: Equatable, Sendable {
    /// Seconds left on each actor's social timer.
    public var socialTimers: [ReferenceKey: Double] = [:]
    /// Each actor's recent partners, skipped as partners until the list empties.
    public var recentPartners: [ReferenceKey: Set<ReferenceKey>] = [:]
    /// Seconds left before each actor's recent list empties.
    public var recentTimers: [ReferenceKey: Double] = [:]
    public var conversations: [SocialConversation] = []
    /// Each actor's default look target and its timers, for `AHEL`. Not saved.
    public var looks: [ReferenceKey: SocialLook] = [:]
    /// The time each body was last checked; no actor reacts to it for 20 s after.
    public var bodyChecks: [ReferenceKey: Double] = [:]
    public var spectators: [ReferenceKey: SocialSpectator] = [:]
    /// The actors walking to a body. Not saved.
    public var finders: [ReferenceKey: SocialFinder] = [:]
    /// The actor each body remembers, most likely its killer. Not saved.
    public var bodyKillers: [ReferenceKey: ReferenceKey] = [:]
    /// The next time actors react to what they detect. Not saved.
    public var nextReaction: Double = 0
    public var lastPass: Double?
    /// The speakers a waiting conversation scene asked to meet their partner. Their
    /// scene has not begun, so the pass does not wait for it. Not saved.
    public var sceneMeetings: Set<ReferenceKey> = []
    public var random = SplitMix64(seed: 0x50C1A1)

    public init() {}

    public func conversation(of actor: ReferenceKey) -> SocialConversation? {
        conversations.first { $0.speaker == actor || $0.partner == actor }
    }

    /// In a conversation, watching a fight, or walking to a body.
    public func isBusy(_ actor: ReferenceKey) -> Bool {
        conversation(of: actor) != nil || spectators[actor] != nil || finders[actor] != nil
    }

    /// The speakers that walk to their partner now.
    public var approachingSpeakers: Set<ReferenceKey> {
        Set(conversations.filter { $0.phase == .approaching }.map(\.speaker))
    }
}
