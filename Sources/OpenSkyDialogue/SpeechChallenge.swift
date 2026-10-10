// Which speech challenge a response wins: the condition that gates it. Measured on
// Skyrim.esm: success lines test `GetBribeSuccess` (654) == 1, `GetIntimidateSuccess`
// (655) == 1, or Speechcraft (actor value 17) >= a global. See docs/engine/dialogue.md.

import OpenSkyFormatsESM

nonisolated public enum SpeechChallenge: Equatable, Sendable {
    case bribe
    case intimidate
    case persuade

    /// The story-manager event code the win sends.
    public var eventCode: String {
        switch self {
        case .bribe: "BRIB"
        case .intimidate: "INTM"
        case .persuade: "FLAT"
        }
    }

    /// The misc stat a win counts.
    public var statName: String {
        switch self {
        case .bribe: "Bribes"
        case .intimidate: "Intimidations"
        case .persuade: "Persuasions"
        }
    }

    static let getActorValue: UInt16 = 14
    static let speechcraft: UInt32 = 17
    static let getBribeSuccess: UInt16 = 654
    static let getIntimidateSuccess: UInt16 = 655

    /// The challenge `info` wins when it is said, or nil for a line with no speech check.
    public static func won(by info: TopicInfo) -> SpeechChallenge? {
        for condition in info.conditions.conditions {
            switch (condition.functionIndex, condition.comparison, condition.comparisonValue) {
            case (getBribeSuccess, .equal, .value(1)): return .bribe
            case (getIntimidateSuccess, .equal, .value(1)): return .intimidate
            case (getActorValue, .greaterThanOrEqual, _)
                where condition.parameter1.rawValue == speechcraft:
                return .persuade
            default: continue
            }
        }
        return nil
    }
}
