// The `CRIM` and `STOL` chunks (issue #504, roadmap item 21.5): the ledger
// round trip, the stolen split laid back over `INVN`'s totals, and the
// absent-chunk cases that keep a law-abiding save byte-identical to what this
// encoder produced before either chunk existed.

import Foundation
@testable import opensky
import Testing

@MainActor
struct CrimeSaveTests {
    private let hold = ReferenceKey.plugin(name: "base.esm", objectID: 0x10)
    private let companions = ReferenceKey.plugin(name: "base.esm", objectID: 0x11)
    private let generated = ReferenceKey.generated(7)
    private let sword = FormID(0x1000)
    private let arrow = FormID(0x1001)

    private static func encode(_ snapshot: WorldStateSnapshot) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    private func roundTrip<Component: WorldStateComponent>(
        _ component: Component,
        for key: ReferenceKey = .player
    ) throws -> Component? {
        let store = WorldStateStore()
        store.set(component, for: key, in: nil)
        let file = try OpenSkySaveDecoder.decode(Self.encode(store.snapshot()))
        return file.snapshot.entries.first { $0.key == key }?.delta.component(Component.self)
    }

    // MARK: - CRIM

    @Test func bountiesAndCountsSurviveTheRoundTrip() throws {
        let ledger = CrimeLedgerState(entries: [
            CrimeLedgerEntry(
                faction: hold,
                gold: 1045,
                counts: CrimeCounts(theft: 3, assault: 1, murder: 1, trespass: 2)
            ),
            CrimeLedgerEntry(faction: companions, gold: 0, counts: CrimeCounts(assault: 4)),
            CrimeLedgerEntry(faction: generated, gold: 25)
        ])

        let restored = try #require(try roundTrip(ledger))

        #expect(restored == ledger)
        #expect(restored.gold(for: hold) == 1045)
        #expect(restored.counts(for: hold).murder == 1)
        // A row with counts and no gold survives, which is what an unwitnessed
        // crime leaves behind.
        #expect(restored.gold(for: companions) == 0)
        #expect(restored.counts(for: companions).assault == 4)
        // Key order, plugin keys before generated ones.
        #expect(restored.factions == [hold, companions, generated])
    }

    /// A bounty is progress the player made, so a faction this load order no
    /// longer carries is kept rather than dropped — the rule an owned perk and
    /// a stored membership follow.
    @Test func aRowNamingAnUnresolvableFactionSurvives() throws {
        let ledger = CrimeLedgerState(entries: [
            CrimeLedgerEntry(faction: .plugin(name: "gone.esp", objectID: 0x99), gold: 40)
        ])

        #expect(try roundTrip(ledger) == ledger)
    }

    @Test func aLawAbidingSessionWritesNoChunk() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: hold, in: nil)
        let bytes = Self.encode(store.snapshot())

        #expect(!Self.contains(tag: OpenSkySaveFormat.ChunkTag.crimeLedgers, in: bytes))
        #expect(!Self.contains(tag: OpenSkySaveFormat.ChunkTag.stolenGoods, in: bytes))
    }

    /// A duplicate row collapses on load rather than restoring two answers to
    /// "what does the player owe this faction".
    @Test func aDuplicateRowCollapsesOnLoad() throws {
        let store = WorldStateStore()
        store.set(
            CrimeLedgerState(entries: [CrimeLedgerEntry(faction: hold, gold: 40)]),
            for: .player,
            in: nil
        )
        let file = try OpenSkySaveDecoder.decode(Self.encode(store.snapshot()))
        let restored = try #require(
            file.snapshot.entries.first { $0.key == .player }?
                .delta.component(CrimeLedgerState.self)
        )

        #expect(restored.count == 1)
        #expect(restored.gold(for: hold) == 40)
    }

    // MARK: - STOL

    /// `INVN` carries the totals and `STOL` carries the split, so the two
    /// together restore the same stacks the session held.
    @Test func theStolenSplitSurvivesTheRoundTrip() throws {
        let inventory = ReferenceInventoryState(stacks: [
            InventoryStack(item: arrow, count: 11),
            InventoryStack(item: arrow, count: 1, stolen: true),
            InventoryStack(item: sword, count: 1, stolen: true)
        ])

        let restored = try #require(try roundTrip(inventory))

        #expect(restored == inventory)
        #expect(restored.count(of: arrow) == 12)
        #expect(restored.stolenCount(of: arrow) == 1)
        #expect(restored.count(of: arrow, stolen: false) == 11)
        #expect(restored.stolenCount(of: sword) == 1)
        #expect(restored.count(of: sword, stolen: false) == 0)
    }

    /// An inventory with nothing stolen writes no `STOL` chunk, so its bytes
    /// match what this encoder produced before the chunk existed.
    @Test func anHonestInventoryWritesNoStolenChunk() {
        let store = WorldStateStore()
        store.set(
            ReferenceInventoryState(stacks: [InventoryStack(item: sword, count: 1)]),
            for: .player,
            in: nil
        )
        let bytes = Self.encode(store.snapshot())

        #expect(Self.contains(tag: OpenSkySaveFormat.ChunkTag.inventories, in: bytes))
        #expect(!Self.contains(tag: OpenSkySaveFormat.ChunkTag.stolenGoods, in: bytes))
    }

    /// Two sessions that reached the same end state write the same bytes, which
    /// is the determinism rule the whole container is built on.
    @Test func theSameLedgerAndSplitEncodeToTheSameBytes() {
        let first = WorldStateStore()
        let second = WorldStateStore()
        for store in [first, second] {
            store.set(
                CrimeLedgerState(entries: [
                    CrimeLedgerEntry(faction: hold, gold: 40, counts: CrimeCounts(assault: 1))
                ]),
                for: .player,
                in: nil
            )
            store.set(
                ReferenceInventoryState(stacks: [
                    InventoryStack(item: arrow, count: 3),
                    InventoryStack(item: arrow, count: 2, stolen: true)
                ]),
                for: .player,
                in: nil
            )
        }

        #expect(Self.encode(first.snapshot()) == Self.encode(second.snapshot()))
    }

    /// A stolen count larger than the inventory holds is clamped rather than
    /// failing the whole save — the invariant belongs to the component.
    @Test func anImpossibleStolenCountClampsRatherThanFailingTheLoad() {
        let inventory = ReferenceInventoryState(stacks: [
            InventoryStack(item: sword, count: 2)
        ])

        let marked = inventory.markingStolen(sword, count: 9)
        #expect(marked.stolenCount(of: sword) == 2)
        #expect(marked.count(of: sword) == 2)
    }

    private static func contains(tag: String, in bytes: Data) -> Bool {
        bytes.range(of: Data(tag.utf8)) != nil
    }
}
