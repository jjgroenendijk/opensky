// Friends let the player take cheap things that belong to their faction. UESP
// "Skyrim:Disposition", Relationship Rank: the allowance works "only on items that
// belong to that person's faction, not items that are owned by that person", and "is
// only evaluated once", so a friend who later becomes an ally keeps the friend value.
// See docs/engine/crime.md.

public import OpenSkyCrimeInterface
public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyInventoryInterface

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

    /// Clears the stolen flag on what the player stole from a friend's faction, when
    /// the friend's allowance covers it. Runs every tick, and acts only when a
    /// relationship, a membership, or the record of stolen items changed.
    public func advanceFavour() {
        guard let runtime = reporter?.runtime, let inventory = world.inventory else { return }
        let revision = runtime.revision(of: [.relationships, .factions, .stolenOrigins])
        guard revision != favourRevision else { return }
        favourRevision = revision
        for origin in runtime.stolenOrigins().origins {
            guard
                let allowance = favourAllowance(in: origin.owner),
                world.itemValue(of: origin.item) <= Int64(allowance)
            else { continue }
            inventory.clearStolen(origin.item, count: origin.count, in: .player)
            runtime.forgetStolen(origin.item, from: origin.owner)
        }
    }
}
