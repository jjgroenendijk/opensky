import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// What one award of character experience did.
nonisolated public struct PlayerLevelUpReport: Equatable, Sendable {
    /// The level before and after.
    public let previousLevel: Int
    public let level: Int
    /// Experience left banked toward the next level.
    public let carriedExperience: Float
    /// Perk points owned after the award.
    public let perkPoints: Int
    /// Attribute picks owed after the award.
    public let pendingAttributePicks: Int
    /// Levels the banked experience has earned that wait for the skills menu.
    public var levelsReady = 0

    public var levelsGained: Int {
        max(0, level - previousLevel)
    }

    public var didLevel: Bool {
        level > previousLevel
    }

    public init(
        previousLevel: Int,
        level: Int,
        carriedExperience: Float,
        perkPoints: Int,
        pendingAttributePicks: Int,
        levelsReady: Int = 0
    ) {
        self.previousLevel = previousLevel
        self.level = level
        self.carriedExperience = carriedExperience
        self.perkPoints = perkPoints
        self.pendingAttributePicks = pendingAttributePicks
        self.levelsReady = levelsReady
    }
}

/// Why an attribute pick or perk-point spend was refused. Not a bool, because the level-up
/// screen shows each case as the reason a button is disabled.
nonisolated public enum PlayerProgressError: Error, Equatable, Sendable {
    /// No attribute pick is owed.
    case noAttributePickOwed
    /// The perk-point pool is empty.
    case noPerkPoints
    /// The perk was refused by the tree (`PerkSpendRefusal` says which rule).
    case perkRefused(PerkSpendRefusal)
}
