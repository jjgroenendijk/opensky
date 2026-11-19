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
    public var phase: Phase
    /// Where the speaker walks; nil before the first walk.
    public var goal: SIMD3<Float>?

    public init(
        speaker: ReferenceKey, partner: ReferenceKey, startedAt: Double,
        answerSeconds: Double = SocialLimits.answerSeconds,
        phase: Phase = .waitingForAnswer, goal: SIMD3<Float>? = nil
    ) {
        self.speaker = speaker
        self.partner = partner
        self.startedAt = startedAt
        self.answerSeconds = answerSeconds
        self.phase = phase
        self.goal = goal
    }
}

/// One actor watching a fight.
nonisolated public struct SocialSpectator: Equatable, Sendable {
    public let fighter: ReferenceKey
    /// The last time the fighter was seen fighting.
    public var lastSeenFighting: Double
    /// The last comment, or nil before the first.
    public var lastComment: Double?
    /// A watcher in a scene keeps its scene's package; the scene's flags decide.
    public let inScene: Bool

    public init(
        fighter: ReferenceKey, lastSeenFighting: Double, lastComment: Double? = nil,
        inScene: Bool = false
    ) {
        self.fighter = fighter
        self.lastSeenFighting = lastSeenFighting
        self.lastComment = lastComment
        self.inScene = inScene
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
    /// What each walker looks at, for `AHEL`.
    public var lookTargets: [ReferenceKey: ReferenceKey] = [:]
    /// The time each body was last checked; no actor reacts to it for 20 s after.
    public var bodyChecks: [ReferenceKey: Double] = [:]
    public var spectators: [ReferenceKey: SocialSpectator] = [:]
    public var lastPass: Double?
    /// Where each actor stood at the last pass, to see who walks. Not saved.
    public var lastPosition: [ReferenceKey: SIMD3<Float>] = [:]
    public var random = SplitMix64(seed: 0x50C1A1)

    public init() {}

    public func conversation(of actor: ReferenceKey) -> SocialConversation? {
        conversations.first { $0.speaker == actor || $0.partner == actor }
    }

    /// In a conversation or watching a fight.
    public func isBusy(_ actor: ReferenceKey) -> Bool {
        conversation(of: actor) != nil || spectators[actor] != nil
    }

    /// The speakers that walk to their partner now.
    public var approachingSpeakers: Set<ReferenceKey> {
        Set(conversations.filter { $0.phase == .approaching }.map(\.speaker))
    }
}
