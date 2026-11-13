// How many blows from the player a friend or an ally takes before it fights back, from
// the friendly fire settings. See docs/engine/hostility.md#friendly-fire.

import Foundation
public import OpenSkyGameData

nonisolated public struct FriendlyFireSettings: Equatable, Sendable {
    /// `fFriendHitTimer`: seconds after which a counted blow is forgotten.
    public var hitTimer: Float = 10
    /// `fFriendMinimumLastHitTime`: a blow this soon after the last one does not count.
    public var minimumLastHitTime: Float = 0.5
    /// `iFriendHitCombatAllowed`: blows a friend in combat takes before it attacks.
    public var friendCombatAllowed = 3
    /// `iFriendHitNonCombatAllowed`: the same for a friend out of combat.
    public var friendNonCombatAllowed = 0
    /// `iAllyHitCombatAllowed`: the same for an ally in combat.
    public var allyCombatAllowed = 1000
    /// `iAllyHitNonCombatAllowed`: the same for an ally out of combat.
    public var allyNonCombatAllowed = 3

    /// The Creation Kit wiki: a count of 1000 or more is no limit.
    public static let unlimited = 1000

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fFriendHitTimer", into: &settings, \.hitTimer)
        store.read("fFriendMinimumLastHitTime", into: &settings, \.minimumLastHitTime)
        store.read("iFriendHitCombatAllowed", into: &settings, \.friendCombatAllowed)
        store.read("iFriendHitNonCombatAllowed", into: &settings, \.friendNonCombatAllowed)
        store.read("iAllyHitCombatAllowed", into: &settings, \.allyCombatAllowed)
        store.read("iAllyHitNonCombatAllowed", into: &settings, \.allyNonCombatAllowed)
        return settings
    }

    /// The blows an actor with `reaction` toward the player takes before it attacks;
    /// nil for a neutral or an enemy, which attacks at once.
    public func allowedHits(for reaction: ActorReaction?, inCombat: Bool) -> Int? {
        switch reaction {
        case .friend: inCombat ? friendCombatAllowed : friendNonCombatAllowed
        case .ally: inCombat ? allyCombatAllowed : allyNonCombatAllowed
        case .neutral, .enemy, nil: nil
        }
    }
}
