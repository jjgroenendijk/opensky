// How often an NPC may speak outside a conversation: the voice gap, the force greet wait,
// and the combat line windows and chances. Each comes from the install; where the wiki
// does not say how a setting applies, the use is OpenSky's reading
// (docs/engine/dialogue.md#speech-timers).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct SpeechTimerSettings: Equatable, Sendable {
    /// `fGameplayVoiceFilePadding`: "seconds of silence that Skyrim inserts between
    /// consecutive voice lines" (<https://ck.uesp.net/wiki/Category:Settings>).
    public var voiceFilePadding: Float = 0.5
    /// `fAIForceGreetingTimer`: "Time until an NPC can initialize a force greeting again".
    public var forceGreetingSeconds: Float = 3
    /// `fCombatDialogueAttackMinElapsedTime` and `...Max...`: an NPC's next attack line
    /// waits a random time in this window.
    public var attackLineMinSeconds: Float = 5
    public var attackLineMaxSeconds: Float = 10
    /// `fCombatSpeakAttackChance` and `fCombatSpeakHitChance`: the chance, 0 to 1, that
    /// an attack or a hit taken speaks once its window has passed.
    public var attackLineChance: Float = 0.01
    public var hitLineChance: Float = 0.01

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fGameplayVoiceFilePadding", into: &settings, \.voiceFilePadding)
        store.read("fAIForceGreetingTimer", into: &settings, \.forceGreetingSeconds)
        store.read(
            "fCombatDialogueAttackMinElapsedTime", into: &settings, \.attackLineMinSeconds
        )
        store.read(
            "fCombatDialogueAttackMaxElapsedTime", into: &settings, \.attackLineMaxSeconds
        )
        store.read("fCombatSpeakAttackChance", into: &settings, \.attackLineChance)
        store.read("fCombatSpeakHitChance", into: &settings, \.hitLineChance)
        return settings
    }

    /// A voiced line's seconds with the gap the next line waits for.
    public func padded(_ seconds: Float) -> Float {
        seconds + (voiceFilePadding.isFinite ? max(voiceFilePadding, 0) : 0)
    }

    /// Seconds before `line` may come again from the same speaker. `unit` in 0...1 picks
    /// a point in the attack window.
    public func wait(after line: NPCSpeechLine, unit: Float) -> Double {
        switch line {
        case .forceGreeting:
            return Double(finite(forceGreetingSeconds))
        case .combatAttack, .combatHit:
            let low = finite(min(attackLineMinSeconds, attackLineMaxSeconds))
            let high = finite(max(attackLineMinSeconds, attackLineMaxSeconds))
            let blend = unit.isFinite ? min(max(unit, 0), 1) : 0
            return Double(low + (high - low) * blend)
        }
    }

    /// The chance, 0 to 1, that `line` speaks when its wait has passed.
    public func chance(of line: NPCSpeechLine) -> Float {
        let chance: Float = switch line {
        case .forceGreeting: 1
        case .combatAttack: attackLineChance
        case .combatHit: hitLineChance
        }
        return chance.isFinite ? min(max(chance, 0), 1) : 0
    }

    private func finite(_ value: Float) -> Float {
        value.isFinite ? max(value, 0) : 0
    }
}

/// A line an NPC says on its own, outside a conversation.
nonisolated public enum NPCSpeechLine: Hashable, Sendable {
    case forceGreeting
    case combatAttack
    case combatHit

    /// The DIAL subtype a combat line is picked from; nil for a force greet.
    public var subtype: FourCC? {
        switch self {
        case .forceGreeting: nil
        case .combatAttack: "ATCK"
        case .combatHit: "HIT_"
        }
    }
}

/// When each speaker may next say each kind of line, in seconds of the caller's clock.
nonisolated public struct NPCSpeechClock: Equatable, Sendable {
    private struct Slot: Hashable, Sendable {
        let speaker: ReferenceKey
        let line: NPCSpeechLine
    }

    private var readyAt: [Slot: Double] = [:]

    public init() {}

    public func isReady(_ line: NPCSpeechLine, speaker: ReferenceKey, now: Double) -> Bool {
        now >= readyAt[Slot(speaker: speaker, line: line)] ?? -.infinity
    }

    public mutating func note(
        _ line: NPCSpeechLine, speaker: ReferenceKey, now: Double, wait: Double
    ) {
        readyAt[Slot(speaker: speaker, line: line)] = now + max(0, wait)
    }

    public mutating func reset() {
        readyAt = [:]
    }
}
