// Theft at the choke points (issue #504, roadmap item 21.5): a take out of the
// world through `WorldItemRuntime`, and a take out of a container through
// `ContainerSession`.
//
// Both go through `CrimeReporter`, so the two paths cannot disagree about what
// counts as theft or about what it costs. The chain under them is the M12
// acceptance chain, which already places an NPC-owned loose sword and an
// unowned chest — the two cases the hook has to tell apart.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct CrimeTheftHookTests {
    private typealias Chain = M12AcceptanceChain

    private let hold = CrimeFixture.key(CrimeFixture.Factions.hold)

    /// The session facts a crime needs, answered from the chain: the owner is
    /// whatever the reference or its cell claims, the place answers to the
    /// hold, and an item is worth what the fixture says.
    private final class FakeCrimeWorld: CrimeWorld {
        var owners: [ReferenceKey: ReferenceOwner] = [:]
        var faction: ReferenceKey? = CrimeFixture.key(CrimeFixture.Factions.hold)
        var values: [FormID: Int64] = [:]
        var actor = CrimeActor.player

        func crimeOwner(of key: ReferenceKey) -> ReferenceOwner? {
            owners[key]
        }

        func crimeFaction(in cell: CellSceneLocation?) -> ReferenceKey? {
            faction
        }

        func crimeCell(of key: ReferenceKey) -> CellSceneLocation? {
            M12AcceptanceChain.cell
        }

        func crimeItemValue(of item: FormID) -> Int64 {
            values[item] ?? 0
        }

        func crimeActor(_ key: ReferenceKey) -> CrimeActor {
            actor
        }
    }

    /// The chain with a crime reporter attached, a live witness, and the loose
    /// sword marked as somebody else's property.
    @MainActor
    private struct Harness {
        let chain: Chain
        let world: FakeCrimeWorld
        let reporter: CrimeReporter

        init(witnessed: Bool = true, owned: Bool = true) throws {
            chain = try Chain()
            world = FakeCrimeWorld()
            world.values[InventoryBaselineFixture.sword] = 25
            if owned {
                world.owners[Chain.key(Chain.looseSwordReference)] =
                    .actor(CrimeFixture.key(CrimeFixture.Actors.shopkeeper))
                world.owners[Chain.key(Chain.chestReference)] =
                    .actor(CrimeFixture.key(CrimeFixture.Actors.shopkeeper))
            }
            reporter = try CrimeReporter(
                runtime: CrimeRuntime(
                    store: chain.store, factions: CrimeFixture.factionStore()
                ),
                world: world
            )
            if witnessed {
                reporter.witnesses = FixedCrimeWitnesses(
                    watching: .player, by: [CrimeFixture.key(CrimeFixture.Actors.resident)]
                )
            }
            chain.runtime.crime = reporter
        }
    }

    // MARK: - Taking from the world

    /// The acceptance shape in miniature: a witnessed take of an owned item
    /// marks the stack stolen and accrues half its value.
    @Test func aWitnessedTakeOfAnOwnedItemIsStolenAndCostsHalfItsValue() throws {
        let harness = try Harness()

        let outcome = try harness.chain.runtime.take(
            Chain.take(Chain.looseSwordReference, base: InventoryBaselineFixture.sword)
        )

        #expect(outcome.stolen)
        #expect(outcome.bounty == 12) // 25 gold, halved and rounded down.
        #expect(harness.reporter.runtime.crimeGold(of: hold) == 12)
        #expect(harness.reporter.runtime.crimeCounts(of: hold).theft == 1)
        #expect(
            harness.chain.runtime.inventory
                .stolenCount(of: InventoryBaselineFixture.sword, in: harness.chain.player) == 1
        )
    }

    /// The same take unwitnessed still marks the stack — "even if you were able
    /// to steal the item without being detected"
    /// (<https://en.uesp.net/wiki/Skyrim:Crime>) — and accrues nothing.
    @Test func anUnwitnessedTakeMarksTheStackAndAccruesNothing() throws {
        let harness = try Harness(witnessed: false)

        let outcome = try harness.chain.runtime.take(
            Chain.take(Chain.looseSwordReference, base: InventoryBaselineFixture.sword)
        )

        #expect(outcome.stolen)
        #expect(outcome.bounty == 0)
        #expect(harness.reporter.runtime.crimeGold(of: hold) == 0)
        #expect(harness.reporter.runtime.crimeCounts(of: hold).theft == 1)
        #expect(
            harness.chain.runtime.inventory
                .stolenCount(of: InventoryBaselineFixture.sword, in: harness.chain.player) == 1
        )
    }

    /// An unowned item is nobody's: no bounty, no marker, no ledger row.
    @Test func takingAnUnownedItemIsNoCrime() throws {
        let harness = try Harness(owned: false)

        let outcome = try harness.chain.runtime.take(
            Chain.take(Chain.looseSwordReference, base: InventoryBaselineFixture.sword)
        )

        #expect(!outcome.stolen)
        #expect(outcome.bounty == 0)
        #expect(harness.reporter.runtime.ledger().isEmpty)
        #expect(
            harness.chain.runtime.inventory
                .stolenCount(of: InventoryBaselineFixture.sword, in: harness.chain.player) == 0
        )
    }

    /// Property this actor may use is not theft, even though it plainly has an
    /// owner — the same rule a faction-owned chest and a shopkeeper's own
    /// counter both follow.
    @Test func takingPropertyTheActorMayUseIsNoCrime() throws {
        let harness = try Harness()
        harness.world.actor = CrimeActor(
            key: .player, base: CrimeFixture.key(CrimeFixture.Actors.shopkeeper)
        )

        let outcome = try harness.chain.runtime.take(
            Chain.take(Chain.looseSwordReference, base: InventoryBaselineFixture.sword)
        )

        #expect(!outcome.stolen)
        #expect(harness.reporter.runtime.ledger().isEmpty)
    }

    /// A session with no crime runtime takes exactly as it did before crime
    /// existed: everything is honest goods.
    @Test func aSessionWithNoCrimeRuntimeTakesHonestly() throws {
        let chain = try Chain()

        let outcome = try chain.runtime.take(
            Chain.take(Chain.looseSwordReference, base: InventoryBaselineFixture.sword)
        )

        #expect(!outcome.stolen)
        #expect(outcome.bounty == 0)
    }

    // MARK: - Taking from a container

    /// Opening an owned container is not a crime; taking out of it is, and the
    /// goods arrive marked.
    @Test func takingFromAnOwnedContainerIsTheftAndMarksWhatMoves() throws {
        let harness = try Harness()
        let session = try harness.chain.runtime.openContainer(
            Chain.search(Chain.chestReference, base: InventoryBaselineFixture.chest)
        )
        #expect(session.ownership.isTheft)
        #expect(harness.reporter.runtime.ledger().isEmpty)

        let bounty = try session.take(InventoryBaselineFixture.lockpick, count: 2)

        #expect(bounty == 0) // A lockpick's fixture value is zero.
        #expect(harness.reporter.runtime.crimeCounts(of: hold).theft == 1)
        #expect(
            harness.chain.runtime.inventory
                .stolenCount(of: InventoryBaselineFixture.lockpick, in: harness.chain.player)
                == 2
        )
    }

    /// "Taking your own items out of an owned container ... are not considered
    /// stealing" (same page): an unowned container hands over honest goods.
    @Test func takingFromAnUnownedContainerIsNoCrime() throws {
        let harness = try Harness(owned: false)
        let session = try harness.chain.runtime.openContainer(
            Chain.search(Chain.chestReference, base: InventoryBaselineFixture.chest)
        )

        #expect(!session.ownership.isTheft)
        try session.take(InventoryBaselineFixture.lockpick, count: 1)

        #expect(harness.reporter.runtime.ledger().isEmpty)
        #expect(
            harness.chain.runtime.inventory
                .stolenCount(of: InventoryBaselineFixture.lockpick, in: harness.chain.player)
                == 0
        )
    }
}
