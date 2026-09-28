// Ownership precedence and the "may this actor use it" rule (issue #504,
// roadmap item 21.5).
//
// The three things this pins are the three the crime runtime cannot recover
// from if they are wrong: which `XOWN` wins, what an unresolvable link means,
// and who counts as allowed.

import Foundation
@testable import opensky
import Testing

struct OwnershipResolutionTests {
    // MARK: - Precedence

    /// A reference's own `XOWN` wins over the cell's, and a reference without
    /// one inherits the cell's — which is every crate in a vanilla shop.
    @Test
    func referenceOwnerWinsOverTheCellAndAnUnownedReferenceInheritsIt() throws {
        let resolver = try CrimeFixture.ownershipResolver()
        let shop = RecordOwnership(owner: FormID(CrimeFixture.Factions.shopkeepers))
        let personal = RecordOwnership(owner: FormID(CrimeFixture.Actors.shopkeeper))

        #expect(
            resolver.owner(reference: personal, cell: shop)
                == .actor(CrimeFixture.key(CrimeFixture.Actors.shopkeeper))
        )
        #expect(
            resolver.owner(reference: nil, cell: shop)
                == .faction(CrimeFixture.key(CrimeFixture.Factions.shopkeepers), requiredRank: 0)
        )
        #expect(resolver.owner(reference: nil, cell: nil) == nil)
    }

    /// A link the load order carries a FACT for is a faction owner; anything
    /// else is an actor owner, including a link no record resolves. Reading a
    /// dangling owner as "unowned" would make a shop free to loot the moment a
    /// plugin went missing.
    @Test
    func aLinkWithNoFactionRecordIsAnActorOwnerRatherThanUnowned() throws {
        let resolver = try CrimeFixture.ownershipResolver()
        let dangling = RecordOwnership(owner: FormID(0xDEAD))

        #expect(resolver.owner(of: dangling) == .actor(CrimeFixture.key(0xDEAD)))
    }

    /// An absent `XRNK` means rank 0, the lowest rank vanilla authors, so an
    /// ordinary member of the owning faction may use the property.
    @Test
    func anAbsentRankMeansRankZero() throws {
        let resolver = try CrimeFixture.ownershipResolver()
        let owned = RecordOwnership(owner: FormID(CrimeFixture.Factions.shopkeepers))

        #expect(
            resolver.owner(of: owned)
                == .faction(CrimeFixture.key(CrimeFixture.Factions.shopkeepers), requiredRank: 0)
        )
    }

    /// A null `XOWN` is no owner at all rather than an owner named zero.
    @Test
    func aNullOwnerLinkIsNoOwnership() throws {
        let unowned = try CrimeFixture.cell(location: CrimeFixture.Locations.shop)
        #expect(RecordOwnership(cell: unowned) == nil)

        let owned = try CrimeFixture.cell(owner: CrimeFixture.Factions.shopkeepers)
        #expect(RecordOwnership(cell: owned)?.owner == FormID(CrimeFixture.Factions.shopkeepers))
    }

    // MARK: - The verdict

    /// The player owns no NPC_ record, so property belonging to an actor is
    /// never theirs; the actor placed from that record may use it.
    @Test
    func actorOwnedPropertyMatchesOnTheBaseRecord() throws {
        let resolver = try CrimeFixture.ownershipResolver()
        let owner = RecordOwnership(owner: FormID(CrimeFixture.Actors.shopkeeper))

        #expect(resolver.verdict(
            for: CrimeFixture.player(), reference: owner, cell: nil
        ).isTheft)
        #expect(!resolver.verdict(
            for: CrimeFixture.actor(0x700, base: CrimeFixture.Actors.shopkeeper),
            reference: owner,
            cell: nil
        ).isTheft)
        // A different actor placed from a different base is still a thief.
        #expect(resolver.verdict(
            for: CrimeFixture.actor(0x701, base: CrimeFixture.Actors.resident),
            reference: owner,
            cell: nil
        ).isTheft)
    }

    /// Faction-owned property needs membership *at or above* the authored rank.
    @Test
    func factionOwnedPropertyNeedsTheAuthoredRank() throws {
        let resolver = try CrimeFixture.ownershipResolver()
        let owner = RecordOwnership(
            owner: FormID(CrimeFixture.Factions.shopkeepers), requiredRank: 2
        )
        let faction = CrimeFixture.Factions.shopkeepers

        #expect(resolver.verdict(
            for: CrimeFixture.player(), reference: owner, cell: nil
        ).isTheft)
        #expect(resolver.verdict(
            for: CrimeFixture.player(memberships: [(faction, 1)]),
            reference: owner,
            cell: nil
        ).isTheft)
        #expect(!resolver.verdict(
            for: CrimeFixture.player(memberships: [(faction, 2)]),
            reference: owner,
            cell: nil
        ).isTheft)
        #expect(!resolver.verdict(
            for: CrimeFixture.player(memberships: [(faction, 5)]),
            reference: owner,
            cell: nil
        ).isTheft)
    }

    /// A negative rank — which vanilla authors to mean "a member the rank
    /// titles do not name" — does not clear a rank-0 requirement.
    @Test
    func aNegativeRankDoesNotClearARankZeroRequirement() throws {
        let resolver = try CrimeFixture.ownershipResolver()
        let owner = RecordOwnership(owner: FormID(CrimeFixture.Factions.shopkeepers))

        #expect(resolver.verdict(
            for: CrimeFixture.player(memberships: [(CrimeFixture.Factions.shopkeepers, -1)]),
            reference: owner,
            cell: nil
        ).isTheft)
    }

    /// An unowned reference in an unowned cell is nobody's, and the verdict
    /// says so rather than reporting a permitted owner.
    @Test
    func nothingClaimedIsUnownedRatherThanPermitted() throws {
        let resolver = try CrimeFixture.ownershipResolver()
        let verdict = resolver.verdict(
            for: CrimeFixture.player(), reference: nil, cell: nil
        )

        #expect(verdict == .unowned)
        #expect(verdict.owner == nil)
        #expect(!verdict.isTheft)
    }

    // MARK: - Cell decode

    /// CELL `XOWN` and `XRNK` decode, which nothing read before this issue.
    /// Vanilla authors `XOWN` on every owned interior and no `XRNK` at all, so
    /// the rank half is decoded defensively and reads as absent.
    @Test
    func cellOwnershipDecodesBothSubrecords() throws {
        let plain = try CrimeFixture.cell(owner: CrimeFixture.Factions.shopkeepers)
        #expect(plain.owner == FormID(CrimeFixture.Factions.shopkeepers))
        #expect(plain.ownerFactionRank == nil)

        let ranked = try CrimeFixture.cell(
            owner: CrimeFixture.Factions.shopkeepers, ownerRank: 3
        )
        #expect(ranked.ownerFactionRank == 3)
        #expect(RecordOwnership(cell: ranked)?.requiredRank == 3)

        let unowned = try CrimeFixture.cell()
        #expect(unowned.owner == nil)
        #expect(unowned.ownerFactionRank == nil)
    }
}
