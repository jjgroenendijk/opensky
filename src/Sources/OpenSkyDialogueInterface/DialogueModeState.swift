// Dialogue mode: the time an actor stays "in conversation with the player" after
// they talked. Pure rules. See docs/engine/dialogue-mode.md.

import Foundation
public import OpenSkyFormatsESM

/// The dialogue mode countdown of each actor, and of the player, in seconds.
nonisolated public struct DialogueModeState: Equatable, Sendable {
    /// Above this many seconds, a new line sets the full time instead of adding it.
    static let refillLimit: Float = 1

    public private(set) var countdowns: [ReferenceKey: Float] = [:]
    public private(set) var playerCountdown: Float = 0

    public init() {}

    public func countdown(of actor: ReferenceKey) -> Float {
        countdowns[actor] ?? 0
    }

    /// True while the actor counts as in conversation with the player.
    public func isTalking(_ actor: ReferenceKey) -> Bool {
        countdown(of: actor) > 0
    }

    public var talkingActors: Set<ReferenceKey> {
        Set(countdowns.keys)
    }

    /// The actor starts a hello, a greeting, or a line of a conversation with the player.
    public mutating func lineStarted(by actor: ReferenceKey, time: Float) {
        let current = countdown(of: actor)
        set(current > Self.refillLimit ? time : current + time, for: actor)
    }

    /// Dialogue with the player starts: the full time is added for both.
    public mutating func dialogueStarted(with actor: ReferenceKey, time: Float) {
        set(countdown(of: actor) + time, for: actor)
        playerCountdown += time
    }

    /// The start failed, so the actor is not in dialogue mode.
    public mutating func dialogueFailed(with actor: ReferenceKey) {
        set(0, for: actor)
    }

    /// The conversation ends. The actor keeps its own countdown.
    public mutating func dialogueEnded() {
        playerCountdown = 0
    }

    /// Counts down by `seconds`. An actor in `speaking` keeps its time.
    /// - Returns: the actors whose dialogue mode ended, in key order.
    public mutating func advance(
        by seconds: Float, speaking: ReferenceKey? = nil
    ) -> [ReferenceKey] {
        guard seconds > 0, !countdowns.isEmpty else { return [] }
        var ended: [ReferenceKey] = []
        for actor in countdowns.keys.sorted() where actor != speaking {
            let left = countdown(of: actor) - seconds
            set(left, for: actor)
            if left <= 0 {
                ended.append(actor)
            }
        }
        return ended
    }

    private mutating func set(_ value: Float, for actor: ReferenceKey) {
        countdowns[actor] = value > 0 ? value : nil
    }
}
