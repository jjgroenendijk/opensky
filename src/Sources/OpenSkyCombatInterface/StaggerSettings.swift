// The stagger chance, its limits, and the disarm perk chances, from the `fStagger*`,
// `iStaggerAttackChance`, and `iPerk*DisarmChance` settings. `HitReactionRule` holds
// the rule (docs/engine/hit-reactions.md).

import Foundation
public import OpenSkyGameData

nonisolated public struct StaggerSettings: Equatable, Sendable {
    /// `iStaggerAttackChance`: percent chance that a hit with a magnitude staggers.
    public var attackChance = 50
    /// `bPlayerAlwaysStaggered`: a hit with a magnitude staggers the player with no roll.
    public var playerAlwaysStaggered = true
    /// `fStaggerMaxDuration`: the longest an actor counts as staggered, in seconds.
    public var maxDuration: Float = 3
    /// `iPerkAttackDisarmChance` and `iPerkBlockDisarmChance`: percent chance that a
    /// disarm spell of `Apply Combat Hit Spell` or `Apply Bashing Spell` takes the weapon.
    public var attackDisarmChance = 50
    public var blockDisarmChance = 50

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("iStaggerAttackChance", into: &settings, \.attackChance)
        store.read("bPlayerAlwaysStaggered", into: &settings, \.playerAlwaysStaggered)
        store.read("fStaggerMaxDuration", into: &settings, \.maxDuration)
        store.read("iPerkAttackDisarmChance", into: &settings, \.attackDisarmChance)
        store.read("iPerkBlockDisarmChance", into: &settings, \.blockDisarmChance)
        return settings
    }
}
