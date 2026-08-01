// InventoryRuntime unit tests (issue #176): the accounting API above
// `WorldStateStore` — add, remove, transfer, carry weight, gold — plus the
// journal entries and snapshot determinism the store gives it for free.
//
// The runtime is `@MainActor` because the store is, so the suite is too.

import Foundation
@testable import opensky
import Testing

@MainActor
struct InventoryRuntimeTests {
    private typealias Fixture = InventoryBaselineFixture

    private let whiterun = CellSceneLocation.exterior(CellCoordinate(x: 5, y: -1))
    private let inn = CellSceneLocation.interior(FormID(0x1234))

    private func runtime(_ store: WorldStateStore) throws -> InventoryRuntime {
        try InventoryRuntime(store: store, baselines: Fixture.resolver())
    }

    private func chest(_ cell: CellSceneLocation? = nil) -> InventoryHolder {
        InventoryHolder(
            key: .plugin(name: "skyrim.esm", objectID: 0x0BAD),
            owner: .container(base: Fixture.chest),
            cell: cell
        )
    }

    private func secondChest() -> InventoryHolder {
        InventoryHolder(
            key: .plugin(name: "skyrim.esm", objectID: 0x0BAE),
            owner: .container(base: Fixture.emptyChest),
            cell: nil
        )
    }

    // MARK: - Reading through the baseline

    @Test func untouchedOwnerReadsItsBaselineAndStaysClean() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        #expect(inventory.count(of: Fixture.lockpick, in: chest()) == 3)
        #expect(inventory.hasRuntimeInventory(chest()) == false)
        #expect(store.dirtyCount == 0)
        #expect(inventory.inventory(of: .player) == .empty)
    }

    /// The first mutation materializes the baseline into the component rather
    /// than storing a difference against it: three lockpicks plus one is four
    /// in the stored state, not "+1".
    @Test func firstMutationMaterializesTheBaseline() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        let updated = try inventory.add(Fixture.lockpick, count: 1, to: chest(whiterun))
        #expect(updated.count(of: Fixture.lockpick) == 4)
        #expect(updated.count(of: Fixture.gold) == 1)
        #expect(inventory.hasRuntimeInventory(chest()))
        #expect(store.dirtyCount == 1)
        #expect(store.dirtyCount(in: whiterun) == 1)
    }

    @Test func removingEverythingLeavesAStoredEmptyInventory() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        let holder = chest()
        try inventory.remove(Fixture.lockpick, count: 3, from: holder)
        try inventory.remove(Fixture.gold, count: 1, from: holder)
        try inventory.remove(Fixture.cuirass, count: 1, from: holder)
        #expect(inventory.inventory(of: holder).isEmpty)
        // Emptied is not the same as untouched: the component still exists, so
        // the container does not refill itself from plugin data.
        #expect(inventory.hasRuntimeInventory(holder))
        #expect(store.dirtyCount == 1)
    }

    @Test func resettingRestoresThePluginBaseline() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        try inventory.remove(Fixture.lockpick, count: 3, from: chest())
        #expect(inventory.reset(chest()))
        #expect(inventory.hasRuntimeInventory(chest()) == false)
        #expect(inventory.count(of: Fixture.lockpick, in: chest()) == 3)
        #expect(store.dirtyCount == 0)
        #expect(inventory.reset(chest()) == false)
    }

    // MARK: - Failure model

    @Test func overRemovingFailsAndWritesNothing() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        #expect(throws: InventoryError.insufficientCount(
            item: Fixture.lockpick, owner: chest().key, requested: 4, available: 3
        )) {
            try inventory.remove(Fixture.lockpick, count: 4, from: chest())
        }
        #expect(store.dirtyCount == 0)
        #expect(store.journalEntries.isEmpty)
        #expect(inventory.count(of: Fixture.lockpick, in: chest()) == 3)
    }

    @Test func nonPositiveCountsAreRefused() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        #expect(throws: InventoryError.nonPositiveCount(0)) {
            try inventory.add(Fixture.gold, count: 0, to: chest())
        }
        #expect(throws: InventoryError.nonPositiveCount(-1)) {
            try inventory.remove(Fixture.gold, count: -1, from: chest())
        }
        #expect(store.dirtyCount == 0)
    }

    // MARK: - Transfer and conservation

    @Test func transferMovesItemsAndConservesTheTotal() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        let source = chest(whiterun)
        let destination = InventoryHolder(key: .player, owner: .player, cell: inn)
        let before = inventory.inventory(of: source).totalCount
            + inventory.inventory(of: destination).totalCount

        try inventory.transfer(Fixture.lockpick, count: 2, from: source, to: destination)

        #expect(inventory.count(of: Fixture.lockpick, in: source) == 1)
        #expect(inventory.count(of: Fixture.lockpick, in: destination) == 2)
        let after = inventory.inventory(of: source).totalCount
            + inventory.inventory(of: destination).totalCount
        #expect(after == before)
        // Each side is attributed to its own cell.
        #expect(store.dirtyCount(in: whiterun) == 1)
        #expect(store.dirtyCount(in: inn) == 1)
    }

    /// Round trip: everything that went out comes back, and both owners end
    /// where they started.
    @Test func transferringBackRestoresBothOwners() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        let source = chest()
        let destination = InventoryHolder.player
        try inventory.transfer(Fixture.lockpick, count: 3, from: source, to: destination)
        try inventory.transfer(Fixture.lockpick, count: 3, from: destination, to: source)
        #expect(inventory.count(of: Fixture.lockpick, in: source) == 3)
        #expect(inventory.count(of: Fixture.lockpick, in: destination) == 0)
        #expect(inventory.inventory(of: destination).isEmpty)
    }

    /// A transfer that cannot complete writes neither side. Both resulting
    /// inventories are computed before either reaches the store, so the total
    /// across owners is unchanged and no journal entry is recorded.
    @Test func failedTransferLeavesBothOwnersUntouched() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        #expect(throws: InventoryError.insufficientCount(
            item: Fixture.sword, owner: chest().key, requested: 1, available: 0
        )) {
            try inventory.transfer(Fixture.sword, count: 1, from: chest(), to: .player)
        }
        #expect(store.dirtyCount == 0)
        #expect(store.journalEntries.isEmpty)
    }

    @Test func transferringToTheSameOwnerIsRefused() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        #expect(throws: InventoryError.sameHolder(chest().key)) {
            try inventory.transfer(Fixture.lockpick, count: 1, from: chest(), to: chest(inn))
        }
        #expect(store.dirtyCount == 0)
    }

    @Test func transferIntoAFullStackReportsOverflowAndWritesNothing() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        let destination = secondChest()
        store.set(
            ReferenceInventoryState(stacks: [
                InventoryStack(item: Fixture.lockpick, count: .max)
            ]),
            for: destination.key
        )
        #expect(throws: InventoryError.countOverflow(
            item: Fixture.lockpick, owner: destination.key
        )) {
            try inventory.transfer(Fixture.lockpick, count: 1, from: chest(), to: destination)
        }
        #expect(inventory.count(of: Fixture.lockpick, in: chest()) == 3)
        #expect(inventory.hasRuntimeInventory(chest()) == false)
    }

    // MARK: - Weight, value and gold

    @Test func carryWeightSumsPerItemWeights() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        // Baseline: 3 lockpicks (0), 1 gold (0), 1 iron cuirass (30).
        #expect(inventory.carriedWeight(of: chest()) == 30)
        try inventory.add(Fixture.sword, count: 2, to: chest())
        #expect(inventory.carriedWeight(of: chest()) == 48)
    }

    /// An item no loaded index describes weighs nothing rather than being
    /// guessed at, and it still counts toward the stack totals.
    @Test func unknownItemsWeighNothingButAreStillHeld() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        let unknown = FormID(0x00BA_DBAD)
        try inventory.add(unknown, count: 5, to: chest())
        #expect(inventory.carriedWeight(of: chest()) == 30)
        #expect(inventory.count(of: unknown, in: chest()) == 5)
    }

    @Test func carriedValueSumsPerItemGoldValues() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        // 3 lockpicks at 5, 1 gold at 1, 1 iron cuirass at 125.
        #expect(inventory.carriedValue(of: chest()) == 141)
    }

    /// Gold is an ordinary stack of an ordinary MISC record, not a separate
    /// currency field.
    @Test func goldIsAnOrdinaryStackOfTheVanillaGoldForm() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        #expect(InventoryRuntime.vanillaGoldFormID == FormID(0x0000_000F))
        #expect(inventory.goldCount(of: chest()) == 1)
        try inventory.transfer(Fixture.gold, count: 1, from: chest(), to: .player)
        #expect(inventory.goldCount(of: .player) == 1)
        #expect(inventory.goldCount(of: chest()) == 0)
        // Weightless, so moving money never changes what an owner carries.
        #expect(inventory.carriedWeight(of: .player) == 0)
    }

    @Test func theGoldFormIsConfigurableRatherThanHardcoded() throws {
        let store = WorldStateStore()
        let inventory = try InventoryRuntime(
            store: store,
            baselines: Fixture.resolver(),
            goldFormID: Fixture.lockpick
        )
        #expect(inventory.goldCount(of: chest()) == 3)
    }

    // MARK: - Equipped set

    @Test func equippingIsStoredAndJournalled() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        let guardHolder = InventoryHolder(
            key: .plugin(name: "skyrim.esm", objectID: 0x0AC7),
            owner: .actor(base: Fixture.guardActor),
            cell: whiterun
        )
        #expect(inventory.inventory(of: guardHolder).isEquipped(Fixture.cuirass))
        #expect(inventory.unequip(Fixture.cuirass, on: guardHolder))
        #expect(inventory.inventory(of: guardHolder).isEquipped(Fixture.cuirass) == false)
        // The item is unequipped, not removed.
        #expect(inventory.count(of: Fixture.cuirass, in: guardHolder) == 2)
        #expect(inventory.equip(Fixture.sword, on: guardHolder))
        #expect(inventory.inventory(of: guardHolder).equipped == [Fixture.sword, Fixture.helmet])
        // Re-equipping something already equipped is a no-op the store rejects.
        #expect(inventory.equip(Fixture.sword, on: guardHolder) == false)
        #expect(store.journalEntries.count { $0.kind == .inventory } == 2)
    }

    @Test func settingTheWholeEquippedSetReplacesIt() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        #expect(inventory.setEquipped([Fixture.helmet, Fixture.cuirass], on: chest()))
        #expect(inventory.inventory(of: chest()).equipped == [Fixture.cuirass, Fixture.helmet])
    }

    // MARK: - Journal

    @Test func mutationsJournalOldAndNewValues() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        try inventory.add(Fixture.gold, count: 10, to: chest(whiterun))
        try inventory.remove(Fixture.gold, count: 4, from: chest(whiterun))

        let entries = store.journalEntries.filter { $0.kind == .inventory }
        #expect(entries.count == 2)
        // The first mutation writes into a clean slot, so it has no old value.
        #expect(entries[0].oldValue == nil)
        #expect(inventoryCount(entries[0].newValue, of: Fixture.gold) == 11)
        #expect(inventoryCount(entries[1].oldValue, of: Fixture.gold) == 11)
        #expect(inventoryCount(entries[1].newValue, of: Fixture.gold) == 7)
        #expect(entries.allSatisfy { $0.cell == whiterun })
        #expect(entries.map(\.sequence) == [1, 2])
    }

    @Test func transferJournalsBothSidesInSourceThenDestinationOrder() throws {
        let store = WorldStateStore()
        let inventory = try runtime(store)
        try inventory.transfer(Fixture.lockpick, count: 1, from: chest(), to: .player)
        let entries = store.journalEntries.filter { $0.kind == .inventory }
        #expect(entries.map(\.key) == [chest().key, ReferenceKey.player])
        #expect(inventoryCount(entries[0].newValue, of: Fixture.lockpick) == 2)
        #expect(inventoryCount(entries[1].newValue, of: Fixture.lockpick) == 1)
    }

    // MARK: - Determinism

    /// The M10 two-stores pattern: two sessions that reach the same end state
    /// through different mutation orders produce equal snapshots, because the
    /// stacks inside the component are sorted rather than insertion ordered.
    @Test func snapshotsAreIndependentOfMutationOrder() throws {
        let first = WorldStateStore()
        let firstInventory = try runtime(first)
        try firstInventory.add(Fixture.sword, count: 1, to: chest())
        try firstInventory.add(Fixture.helmet, count: 2, to: chest())
        try firstInventory.remove(Fixture.lockpick, count: 1, from: chest())

        let second = WorldStateStore()
        let secondInventory = try runtime(second)
        try secondInventory.remove(Fixture.lockpick, count: 1, from: chest())
        try secondInventory.add(Fixture.helmet, count: 1, to: chest())
        try secondInventory.add(Fixture.sword, count: 1, to: chest())
        try secondInventory.add(Fixture.helmet, count: 1, to: chest())

        #expect(first.snapshot() == second.snapshot())
        #expect(first.snapshot().entries.count == 1)
    }

    private func inventoryCount(_ value: WorldStateComponentValue?, of item: FormID) -> Int32? {
        guard let value, case let .inventory(inventory) = value else { return nil }
        return inventory.count(of: item)
    }
}
