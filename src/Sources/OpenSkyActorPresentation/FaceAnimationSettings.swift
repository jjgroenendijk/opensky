// The game settings behind the automatic face: blinks and eye drift by emotion.
// Vanilla values are the Creation Kit wiki's "Category:Settings" table. See
// docs/engine/face-morphs.md.

import Foundation
import OpenSkyFormatsESM
public import OpenSkyGameData

/// How far the eyes drift for one emotion, in radians. Positive heading looks left,
/// positive pitch looks up.
nonisolated public struct EyeOffsetRange: Equatable, Sendable {
    public var headingMin: Float
    public var headingMax: Float
    public var pitchMin: Float
    public var pitchMax: Float

    init(headingMin: Float, headingMax: Float, pitchMin: Float, pitchMax: Float) {
        self.headingMin = headingMin
        self.headingMax = headingMax
        self.pitchMin = pitchMin
        self.pitchMax = pitchMax
    }

    init(_ headingMin: Float, _ headingMax: Float, _ pitchMin: Float, _ pitchMax: Float) {
        self.init(
            headingMin: headingMin, headingMax: headingMax, pitchMin: pitchMin, pitchMax: pitchMax
        )
    }

    static let still = EyeOffsetRange(0, 0, 0, 0)
}

nonisolated public struct FaceAnimationSettings: Equatable, Sendable {
    /// The game names eye ranges for these emotions only; the others use `Neutral`.
    public static let eyeEmotions = ["Angry", "Fear", "Happy", "Neutral", "Sad"]

    /// `fBlinkDelayMin` and `fBlinkDelayMax`: seconds between blinks.
    public var blinkDelayMin: Float = 0.5
    public var blinkDelayMax: Float = 2.5
    /// `fBlinkDownTime`: seconds to close the eyes; `fBlinkUpTime`: seconds to open them.
    public var blinkDownTime: Float = 0.04
    public var blinkUpTime: Float = 0.14
    /// `fEyeHeading...OffsetEmotion<Name>` and `fEyePitch...OffsetEmotion<Name>`.
    public var eyeRanges: [String: EyeOffsetRange] = [
        "Angry": EyeOffsetRange(-0.05, 0.05, -0.05, 0.1),
        "Fear": EyeOffsetRange(-0.05, 0.1, 0.01, 0.01),
        "Happy": EyeOffsetRange(-0.05, 0.1, -0.05, 0.1),
        "Neutral": EyeOffsetRange(-0.05, 0.1, -0.025, 0.1),
        "Sad": EyeOffsetRange(-0.05, 0.1, -0.015, -0.05)
    ]
    /// `fTrackEyeXY` and `fTrackEyeZ`: degrees of eye turn a full `Look` morph shows.
    public var eyeTrackXY: Float = 28
    public var eyeTrackZ: Float = 20
    /// `fAIHeadTrackPickNewOffsetTimer`: seconds between two eye drifts.
    public var eyePickNewOffset: Float = 2

    public static let vanilla = Self()

    public init() {}

    func eyeRange(for emotion: TopicInfo.ResponseEmotion?) -> EyeOffsetRange {
        let name = switch emotion {
        case .anger?: "Angry"
        case .fear?: "Fear"
        case .happy?: "Happy"
        case .sad?: "Sad"
        default: "Neutral"
        }
        return eyeRanges[name] ?? eyeRanges["Neutral"] ?? .still
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fBlinkDelayMin", into: &settings, \.blinkDelayMin)
        store.read("fBlinkDelayMax", into: &settings, \.blinkDelayMax)
        store.read("fBlinkDownTime", into: &settings, \.blinkDownTime)
        store.read("fBlinkUpTime", into: &settings, \.blinkUpTime)
        for name in eyeEmotions {
            var range = settings.eyeRanges[name] ?? .still
            store.read("fEyeHeadingMinOffsetEmotion\(name)", into: &range, \.headingMin)
            store.read("fEyeHeadingMaxOffsetEmotion\(name)", into: &range, \.headingMax)
            store.read("fEyePitchMinOffsetEmotion\(name)", into: &range, \.pitchMin)
            store.read("fEyePitchMaxOffsetEmotion\(name)", into: &range, \.pitchMax)
            settings.eyeRanges[name] = range
        }
        store.read("fTrackEyeXY", into: &settings, \.eyeTrackXY)
        store.read("fTrackEyeZ", into: &settings, \.eyeTrackZ)
        store.read("fAIHeadTrackPickNewOffsetTimer", into: &settings, \.eyePickNewOffset)
        return settings
    }
}
