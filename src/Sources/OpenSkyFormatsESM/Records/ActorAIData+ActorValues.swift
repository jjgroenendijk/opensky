// The AI Data tab's six attributes are actor values 0 to 5 (UESP "Actor Value Indices"),
// so a condition, a script, and the combat rules read them from the actor's values.
// docs/engine/actor-values.md#ai-attributes.

import Foundation

nonisolated extension ActorAIData {
    /// Aggression, Confidence, Energy, Morality, Mood, and Assistance, by actor value index.
    public var actorValues: [Int32: Float] {
        [
            0: Float(aggression.rawValue),
            1: Float(confidence.rawValue),
            2: Float(energy),
            3: Float(morality.rawValue),
            4: Float(mood),
            5: Float(assistance.rawValue)
        ]
    }
}

nonisolated extension ActorConfidence {
    var rawValue: UInt8 {
        switch self {
        case .cowardly: 0
        case .cautious: 1
        case .average: 2
        case .brave: 3
        case .foolhardy: 4
        case let .unknown(raw): raw
        }
    }
}

nonisolated extension ActorMorality {
    var rawValue: UInt8 {
        switch self {
        case .anyCrime: 0
        case .violenceAgainstEnemies: 1
        case .propertyCrimeOnly: 2
        case .noCrime: 3
        case let .unknown(raw): raw
        }
    }
}

nonisolated extension ActorAssistance {
    var rawValue: UInt8 {
        switch self {
        case .helpsNobody: 0
        case .helpsAllies: 1
        case .helpsFriendsAndAllies: 2
        case let .unknown(raw): raw
        }
    }
}
