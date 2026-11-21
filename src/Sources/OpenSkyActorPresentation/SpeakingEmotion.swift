// The emotion value of a speaker: when the game rolls a new one, and how it falls
// back after the line. Pure rules. See docs/engine/face-morphs.md#emotion-while-speaking.

import Foundation

/// The settings of the speaking emotion roll.
nonisolated public struct SpeakingEmotionSettings: Equatable, Sendable {
    /// `iGameplayiSpeakingEmotionListenValue`: the neutral value a roll starts from.
    public var listenValue = 50
    /// `fGameplayiSpeakingEmotionMinDeltaChange` and `...MaxDeltaChange`: percent of
    /// the base value below and above it.
    public var minDeltaPercent: Float = 100
    public var maxDeltaPercent: Float = 100
    /// `fGameplaySpeakingEmotionMinChangeValue` and `...MaxChangeValue`: seconds
    /// between two rolls.
    public var changeSecondsMin: Float = 1.5
    public var changeSecondsMax: Float = 1.5
    /// `iGameplayiSpeakingEmotionDeltaChange`: the fall per update after the line.
    public var settleStep = 10

    public init() {}
}

/// One speaker's emotion value while a line plays and after it.
nonisolated struct SpeakingEmotion: Equatable, Sendable {
    /// The value of the line, which the roll range is built around.
    let base: Int
    private(set) var value: Int
    private(set) var timer: Float = 0

    init(base: UInt32) {
        self.base = Int(min(base, 100))
        value = self.base
    }

    /// The range a roll picks from: `low ..< high`. A low end below 0 becomes 0 and
    /// leaves the high end alone; else the high end stops at 100.
    func range(_ settings: SpeakingEmotionSettings) -> Range<Int> {
        var low = base - Int(Float(base) * settings.minDeltaPercent / 100)
        var high = base + Int(Float(base) * settings.maxDeltaPercent / 100)
        if low < 0 {
            low = 0
        } else {
            high = min(high, 100)
        }
        return low ..< max(high, low)
    }

    /// One update while the line plays. The timer runs only at the listen value, and
    /// a roll jumps straight to its number. `unit` gives two numbers in 0 ..< 1.
    mutating func speak(
        elapsed: Float, settings: SpeakingEmotionSettings, unit: () -> Float
    ) {
        guard value == settings.listenValue else { return }
        timer -= elapsed
        guard timer <= 0 else { return }
        let range = range(settings)
        if !range.isEmpty {
            value = min(range.lowerBound + Int(unit() * Float(range.count)), range.upperBound - 1)
        }
        let spread = max(settings.changeSecondsMax - settings.changeSecondsMin, 0)
        timer = settings.changeSecondsMin + unit() * spread
    }

    /// One update after the line. A value above the listen value falls by the step;
    /// one below it is never raised.
    /// - Returns: false once the value has nothing left to fall.
    mutating func settle(settings: SpeakingEmotionSettings) -> Bool {
        guard value > settings.listenValue else { return false }
        value = max(value - settings.settleStep, settings.listenValue)
        return value > settings.listenValue
    }
}
