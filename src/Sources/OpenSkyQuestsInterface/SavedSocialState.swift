// What a save keeps of one actor's social state: its timers, the conversation it
// started, and when its body was last found. The list of recent partners and the
// fight watchers are not kept, as in the game
// (docs/engine/random-conversations.md#what-a-save-keeps).

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyWorldState

nonisolated public struct SavedSocialState: WorldStateComponent, Sendable {
    /// A conversation as the speaker keeps it.
    nonisolated public struct Conversation: Equatable, Sendable {
        public let partner: ReferenceKey
        public let phase: SocialConversation.Phase
        /// Seconds since `ADIA` fired.
        public let age: Double
        public let answerSeconds: Double
        public let goal: SIMD3<Float>?

        public init(
            partner: ReferenceKey, phase: SocialConversation.Phase, age: Double,
            answerSeconds: Double, goal: SIMD3<Float>?
        ) {
            self.partner = partner
            self.phase = phase
            self.age = age
            self.answerSeconds = answerSeconds
            self.goal = goal
        }
    }

    /// Seconds left on the social timer.
    public var socialTimer: Double?
    /// Seconds left before the recent-partner list empties.
    public var recentTimer: Double?
    /// Seconds since a finder last reacted to this body.
    public var bodyCheckAge: Double?
    public var conversation: Conversation?

    public static var componentKind: WorldStateComponentKind {
        .savedSocialState
    }

    public init(
        socialTimer: Double? = nil, recentTimer: Double? = nil, bodyCheckAge: Double? = nil,
        conversation: Conversation? = nil
    ) {
        self.socialTimer = socialTimer
        self.recentTimer = recentTimer
        self.bodyCheckAge = bodyCheckAge
        self.conversation = conversation
    }
}

nonisolated extension WorldStateComponentKind {
    /// One actor's social timers and conversation. Keyed by the actor.
    public static let savedSocialState = Self(
        rawValue: "savedSocialState", order: 51, affectsCellBuild: false
    )
}

nonisolated extension SocialState {
    /// Each actor's part of the state, with times counted back from `now`, the clock
    /// the social pass reads. A conversation is kept on its speaker.
    public func saved(now: Double) -> [ReferenceKey: SavedSocialState] {
        var saved: [ReferenceKey: SavedSocialState] = [:]
        for (key, seconds) in socialTimers {
            saved[key, default: SavedSocialState()].socialTimer = seconds
        }
        for (key, seconds) in recentTimers {
            saved[key, default: SavedSocialState()].recentTimer = seconds
        }
        for (key, checked) in bodyChecks {
            saved[key, default: SavedSocialState()].bodyCheckAge = max(0, now - checked)
        }
        for talk in conversations {
            saved[talk.speaker, default: SavedSocialState()].conversation = .init(
                partner: talk.partner, phase: talk.phase, age: max(0, now - talk.startedAt),
                answerSeconds: talk.answerSeconds, goal: talk.goal
            )
        }
        return saved
    }

    /// The state a save kept, with its times set against `now`. The next pass counts
    /// its elapsed time from its own first run.
    public init(saved: [ReferenceKey: SavedSocialState], now: Double) {
        self.init()
        for key in saved.keys.sorted() {
            guard let actor = saved[key] else { continue }
            socialTimers[key] = actor.socialTimer
            recentTimers[key] = actor.recentTimer
            bodyChecks[key] = actor.bodyCheckAge.map { now - $0 }
            if let talk = actor.conversation {
                conversations.append(SocialConversation(
                    speaker: key, partner: talk.partner, startedAt: now - talk.age,
                    answerSeconds: talk.answerSeconds, phase: talk.phase, goal: talk.goal
                ))
            }
        }
    }
}
