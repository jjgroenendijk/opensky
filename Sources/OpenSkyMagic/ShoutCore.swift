// The player's shout as a pure state machine: the hold picks how many words, the
// release waits for the graph's `Voice_SpellFire_Event`, and the cooldown follows the
// last word's recovery time. UESP "Skyrim:Dragon Shouts": "Tapping the shout button will
// unleash the weakest version of the shout ... Once the shout is fully charged, your
// character will release it automatically." See docs/engine/shouts.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// How long a hold must last to reach each word.
nonisolated public struct ShoutSettings: Equatable, Sendable {
    /// `fShoutTime1`: the hold that reaches the second word.
    public var secondWordHold: Float = 0.2
    /// `fShoutTime2`: the hold that reaches the third word.
    public var thirdWordHold: Float = 0.9
    /// Ours: a released shout fires after this long when no graph raises the event.
    public var fireWithoutGraphAfter: Float = 1.5

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fShoutTime1", into: &settings, \.secondWordHold)
        store.read("fShoutTime2", into: &settings, \.thirdWordHold)
        return settings
    }
}

nonisolated public enum ShoutPhase: Equatable, Sendable {
    case idle
    /// The key is down and the graph inhales.
    case inhaling(held: Float)
    /// Released with `words` words; the spell waits for the exhale's event.
    case exhaling(words: Int, waited: Float)
}

/// What one frame of the machine asks of the coordinator.
nonisolated public enum ShoutStep: Equatable, Sendable {
    case none
    /// Raise `shoutRelease` on the player's graph.
    case release(words: Int)
    /// Cast the spell of word `words` now.
    case fire(words: Int)
}

nonisolated public struct ShoutMachine: Equatable, Sendable {
    public private(set) var phase = ShoutPhase.idle
    /// Seconds until the next shout.
    public private(set) var cooldown: Float = 0
    /// The length of the running cooldown, for the readout.
    public private(set) var cooldownTotal: Float = 0

    public init() {}

    /// The graph hears `bWantCastVoice` while the player inhales.
    public var wantsVoice: Bool {
        if case .inhaling = phase {
            true
        } else {
            false
        }
    }

    public var isIdle: Bool {
        phase == .idle
    }

    public mutating func begin() {
        guard isIdle, cooldown <= 0 else { return }
        phase = .inhaling(held: 0)
    }

    public mutating func startCooldown(_ seconds: Float) {
        cooldown = max(0, seconds)
        cooldownTotal = cooldown
    }

    /// One frame. `fired` is true when the graph raised `Voice_SpellFire_Event`.
    public mutating func advance(
        held: Bool, delta: Float, unlockedWords: Int, fired: Bool, settings: ShoutSettings
    ) -> ShoutStep {
        cooldown = max(0, cooldown - max(0, delta))
        switch phase {
        case .idle:
            return .none
        case let .inhaling(time):
            let now = held ? time + max(0, delta) : time
            let full = now >= ShoutCore.fullChargeHold(unlocked: unlockedWords, settings: settings)
            guard !held || full else {
                phase = .inhaling(held: now)
                return .none
            }
            let words = ShoutCore.words(held: now, unlocked: unlockedWords, settings: settings)
            phase = .exhaling(words: words, waited: 0)
            return .release(words: words)
        case let .exhaling(words, waited):
            let waited = waited + max(0, delta)
            guard fired || waited >= settings.fireWithoutGraphAfter else {
                phase = .exhaling(words: words, waited: waited)
                return .none
            }
            phase = .idle
            return .fire(words: words)
        }
    }
}

nonisolated public enum ShoutCore {
    /// How many words a hold of `held` seconds shouts, at most `unlocked`.
    public static func words(held: Float, unlocked: Int, settings: ShoutSettings) -> Int {
        let reached = held >= settings.thirdWordHold ? 3 : held >= settings.secondWordHold ? 2 : 1
        return max(1, min(reached, unlocked))
    }

    /// The hold that reaches the last unlocked word, where the shout releases itself.
    public static func fullChargeHold(unlocked: Int, settings: ShoutSettings) -> Float {
        switch unlocked {
        case ...1: 0
        case 2: settings.secondWordHold
        default: settings.thirdWordHold
        }
    }

    /// The word's recovery times `ShoutRecoveryMult`, base 1. UESP "Skyrim:Fortify Shouts":
    /// "A magnitude of 0.2 reduces the ShoutRecoveryMult actor value from ... 1.0 to 0.8."
    public static func cooldown(recovery: Float, multiplier: Float) -> Float {
        max(0, recovery * max(0, multiplier))
    }

    /// Words are unlocked in order, so the count stops at the first locked word.
    public static func unlockedWordCount(_ words: [ReferenceKey?], unlocked: Set<ReferenceKey>)
        -> Int
    {
        words.prefix { $0.map(unlocked.contains) ?? false }.count
    }
}
