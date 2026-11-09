// The expression a face holds from the actor's own state: fear, combat, the line it
// says, or its mood. The order and the weights follow the game
// (docs/engine/face-morphs.md#mood-and-combat).

import Foundation
public import OpenSkyFormatsESM

/// The actor state the face reads each frame.
nonisolated public struct FaceMoodInput: Equatable, Sendable {
    public var isFleeing: Bool
    public var isInCombat: Bool
    /// The player draws or swings a weapon.
    public var isAttacking: Bool
    /// The `Mood` actor value: 0 neutral, 1 anger, 2 fear, 3 happy, 4 sad, 5 surprise,
    /// 6 puzzled, 7 disgusted.
    public var mood: Int

    public init(
        isFleeing: Bool = false, isInCombat: Bool = false, isAttacking: Bool = false,
        mood: Int = 0
    ) {
        self.isFleeing = isFleeing
        self.isInCombat = isInCombat
        self.isAttacking = isAttacking
        self.mood = mood
    }

    public static let calm = Self()
}

nonisolated public enum FacialMoodRules {
    /// `Mood*` targets in `Mood` actor value order. The head TRI has no `MoodNeutral`
    /// shape, so a neutral mood shows nothing.
    public static let moodTargets = [
        "MoodNeutral", "MoodAnger", "MoodFear", "MoodHappy", "MoodSad", "MoodSurprise",
        "MoodPuzzled", "MoodDisgusted"
    ]
    public static let restingMoodWeight: Float = 0.5

    /// The one target the face moves toward. `speaking` is the emotion of the line the
    /// actor says now, if any.
    public static func goal(
        _ input: FaceMoodInput,
        speaking: (emotion: TopicInfo.ResponseEmotion, value: UInt32)?
    ) -> [String: Float] {
        if input.isFleeing {
            return ["DialogueFear": 1]
        }
        if input.isInCombat || input.isAttacking {
            return speaking == nil ? ["CombatAnger": 1] : ["DialogueAnger": 1]
        }
        if let speaking {
            return FacialExpressionCore.emotionWeights(speaking.emotion, value: speaking.value)
        }
        guard input.mood > 0, moodTargets.indices.contains(input.mood) else { return [:] }
        return [moodTargets[input.mood]: restingMoodWeight]
    }

    /// Weight per second a face moves toward `goal`: 2 plus the goal's strength.
    public static func rate(toward goal: [String: Float]) -> Float {
        2 + (goal.values.max() ?? 0)
    }
}
