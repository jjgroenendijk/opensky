// The automatic face: a dialogue emotion held on the speaker's face, and blinking.
// Target names are the expression TRI's own (`DialogueAnger`, `BlinkLeft`, ...), read
// from the head TRI on the install. The blink timing is OpenSky's own.
// See docs/engine/face-morphs.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public enum FacialExpressionCore {
    /// Seconds one blink takes, closed at its middle.
    public static let blinkSeconds: Float = 0.2
    /// Blinks come every 3 to 6 seconds, at a gap each actor keeps.
    public static let shortestBlinkGap: Float = 3
    public static let blinkGapSpread: Float = 3

    /// The TRI target an `INFO` `TRDT` emotion shows, at `value` out of 100.
    /// Neutral shows nothing.
    public static func emotionWeights(
        _ emotion: TopicInfo.Response.Emotion, value: UInt32
    ) -> [String: Float] {
        let name: String? = switch emotion {
        case .anger: "DialogueAnger"
        case .disgust: "DialogueDisgusted"
        case .fear: "DialogueFear"
        case .sad: "DialogueSad"
        case .happy: "DialogueHappy"
        case .surprise: "DialogueSurprise"
        case .puzzled: "DialoguePuzzled"
        case .neutral, .unknown: nil
        }
        guard let name else { return [:] }
        return [name: Float(min(value, 100)) / 100]
    }

    /// How closed both eyes are at `time`, 0 to 1. `seed` spreads actors apart, so a
    /// crowd does not blink together.
    public static func blink(at time: Float, seed: UInt32) -> Float {
        guard time.isFinite else { return 0 }
        let mixed = seed &* 2_654_435_761
        let gap = shortestBlinkGap + Float(mixed % 1000) / 1000 * blinkGapSpread
        let offset = Float((mixed >> 10) % 1000) / 1000 * gap
        let phase = (time + offset).truncatingRemainder(dividingBy: gap)
        guard phase >= 0, phase < blinkSeconds else { return 0 }
        let half = blinkSeconds / 2
        return phase < half ? phase / half : (blinkSeconds - phase) / half
    }

    public static func blinkWeights(_ closed: Float) -> [String: Float] {
        closed > 0 ? ["BlinkLeft": closed, "BlinkRight": closed] : [:]
    }

    /// One frame's automatic weights: the emotion, plus a blink on top.
    public static func weights(
        emotion: [String: Float], blink: Float
    ) -> [String: Float] {
        emotion.merging(blinkWeights(blink)) { max($0, $1) }
    }
}
