// Friends let the player take cheap things that belong to their faction. UESP
// "Skyrim:Disposition", Relationship Rank: the allowance works "only on items that
// belong to that person's faction, not items that are owned by that person", and "is
// only evaluated once", so a friend who later becomes an ally keeps the friend value.
// See docs/engine/crime.md.

import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM

/// The favour rule: values in, gold out.
public enum FavourAllowance {
    /// The highest allowance among the player's friends who belong to `faction`, or
    /// nil when none does. Each friend counts with the rank they first reached as friend.
    public static func gold(
        in faction: ReferenceKey,
        playerRelationships: ActorRelationshipState,
        memberships: (ReferenceKey) -> ActorFactionState?,
        settings: CrimeSettings
    ) -> Int32? {
        playerRelationships.overrides.compactMap { override -> Int32? in
            guard
                override.rank >= 1,
                memberships(override.other)?.isMember(of: faction) == true
            else { return nil }
            return settings.favourAllowance(forRank: override.firstFriendRank ?? override.rank)
        }.max()
    }
}

extension CrimeCoordinator {
    public func favourAllowance(in faction: ReferenceKey) -> Int32? {
        guard let runtime = reporter?.runtime else { return nil }
        return FavourAllowance.gold(
            in: faction,
            playerRelationships: runtime.relationships(of: .player),
            memberships: { [world] in world.factionMemberships(of: $0) },
            settings: runtime.settings
        )
    }
}
