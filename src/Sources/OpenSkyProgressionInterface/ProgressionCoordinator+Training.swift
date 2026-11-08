import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// A trainer the player can buy sessions from.
nonisolated public struct TrainerOffer: Equatable, Sendable {
    public let trainer: ReferenceKey
    public let name: String
    /// The skill's actor value index.
    public let skill: Int32
    public let maximumLevel: Int

    public init(trainer: ReferenceKey, name: String, skill: Int32, maximumLevel: Int) {
        self.trainer = trainer
        self.name = name
        self.skill = skill
        self.maximumLevel = maximumLevel
    }
}

/// What one training attempt did.
nonisolated public enum TrainingOutcome: Equatable, Sendable {
    case trained(skill: Int32, level: Int, gold: Int)
    case refused(TrainingRefusal)
    case unavailable
}
