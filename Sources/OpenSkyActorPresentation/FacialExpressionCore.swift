// The automatic face: a dialogue emotion held on the speaker's face, blinking, and eye
// drift. Target names are the expression TRI's own (`DialogueAnger`, `BlinkLeft`,
// `LookLeft`, ...), read from the head TRI on the install. See docs/engine/face-morphs.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public enum FacialExpressionCore {
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

    /// How closed both eyes are `elapsed` seconds into a blink, 0 to 1: closing over the
    /// down time, then opening over the up time.
    public static func blinkClosure(elapsed: Float, settings: FaceAnimationSettings) -> Float {
        let down = max(settings.blinkDownTime, 0)
        let up = max(settings.blinkUpTime, 0)
        guard elapsed.isFinite, elapsed >= 0, elapsed < down + up else { return 0 }
        if elapsed < down {
            return elapsed / down
        }
        return up > 0 ? 1 - (elapsed - down) / up : 0
    }

    /// The eye drift at `time` for one emotion's range, in radians: a new point in the
    /// range every `interval` seconds. `seed` gives each actor its own drift.
    public static func eyeOffset(
        at time: Float, seed: UInt32, range: EyeOffsetRange, interval: Float
    ) -> HeadLook {
        guard time.isFinite, time >= 0, interval > 0 else { return .forward }
        let cycle = UInt32(truncatingIfNeeded: Int((time / interval).rounded(.down)))
        let roll = SeededRoll(seed: seed, cycle: cycle)
        return HeadLook(
            yaw: HeadTrackingCore.lerp(range.headingMin, range.headingMax, roll.value(5)),
            pitch: HeadTrackingCore.lerp(range.pitchMin, range.pitchMax, roll.value(6))
        )
    }

    /// The `Look` targets that show `offset`; a full weight is the eye track limit.
    public static func eyeWeights(
        _ offset: HeadLook, settings: FaceAnimationSettings
    ) -> [String: Float] {
        func weight(_ angle: Float, limit: Float) -> Float {
            limit > 0 ? min(abs(angle) * 180 / .pi / limit, 1) : 0
        }
        var weights: [String: Float] = [:]
        let heading = weight(offset.yaw, limit: settings.eyeTrackXY)
        let pitch = weight(offset.pitch, limit: settings.eyeTrackZ)
        if heading > 0 {
            weights[offset.yaw > 0 ? "LookLeft" : "LookRight"] = heading
        }
        if pitch > 0 {
            weights[offset.pitch > 0 ? "LookUp" : "LookDown"] = pitch
        }
        return weights
    }

    /// `current` moved toward `goal` by at most `step` on each target; a target missing
    /// from one side counts as 0.
    public static func ease(
        _ current: [String: Float], toward goal: [String: Float], step: Float
    ) -> [String: Float] {
        var result: [String: Float] = [:]
        for name in Set(current.keys).union(goal.keys) {
            let from = current[name] ?? 0
            let to = goal[name] ?? 0
            let next = from + min(max(to - from, -step), step)
            if next > 0 {
                result[name] = next
            }
        }
        return result
    }

    public static func blinkWeights(_ closed: Float) -> [String: Float] {
        closed > 0 ? ["BlinkLeft": closed, "BlinkRight": closed] : [:]
    }

    /// One frame's automatic weights: the emotion and the eyes, plus a blink on top.
    public static func weights(
        emotion: [String: Float], eyes: [String: Float] = [:], blink: Float
    ) -> [String: Float] {
        emotion.merging(eyes) { max($0, $1) }.merging(blinkWeights(blink)) { max($0, $1) }
    }
}
