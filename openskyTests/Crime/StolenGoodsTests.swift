// The stolen flag on inventory stacks (issue #504, roadmap item 21.5): how it
// splits a stack, how it survives a move, and how a take out of an owned
// container marks it.
//
// "Should you steal multiple items of the same type, each item considered
// stolen is tracked separately when dropped" and "as long as this tag is
// present, the item is considered stolen"
// (<https://en.uesp.net/wiki/Skyrim:Crime>) — the two facts that make the flag
// part of the stack key rather than a property of the item.

import Foundation
@testable import opensky
import Testing

@MainActor
struct StolenGoodsTests {
    private let arrow = FormID(0x1001)
    private let sword = FormID(0x1000)
    private let owner = ReferenceKey.player

    // MARK: - The component

    /// Honest and stolen copies of one form are two stacks, ordered honest
    /// first so the bytes stay a pure function of the state.
    @Test func honestAndStolenCopiesAreSeparateStacks() {
        let inventory = ReferenceInventoryState(stacks: [
            InventoryStack(item: arrow, count: 1, stolen: true),
            InventoryStack(item: arrow, count: 11)
        ])

        #expect(inventory.stacks.count == 2)
        #expect(inventory.stacks.map(\.stolen) == [false, true])
        #expect(inventory.count(of: arrow) == 12)
        #expect(inventory.count(of: arrow, stolen: false) == 11)
        #expect(inventory.stolenCount(of: arrow) == 1)
        #expect(inventory.isStolen(arrow))
        #expect(!inventory.isStolen(sword))
    }

    /// Adding to one flavour leaves the other alone.
    @Test func addingStolenCopiesDoesNotTouchTheHonestOnes() throws {
        let start = try ReferenceInventoryState()
            .adding(arrow, count: 5, owner: owner)
            .adding(arrow, count: 2, owner: owner, stolen: true)

        #expect(start.count(of: arrow, stolen: false) == 5)
        #expect(start.stolenCount(of: arrow) == 2)
        #expect(start.totalCount == 7)
    }

    /// Removing spends honest copies first, so an inventory holding both parts
    /// with the ones that carry no consequence.
    @Test func removingSpendsHonestCopiesFirst() throws {
        let start = try ReferenceInventoryState()
            .adding(arrow, count: 3, owner: owner)
            .adding(arrow, count: 2, owner: owner, stolen: true)

        let after = try start.removing(arrow, count: 4, owner: owner)
        #expect(after.count(of: arrow, stolen: false) == 0)
        #expect(after.stolenCount(of: arrow) == 1)

        // The split says the same thing before the removal happens.
        #expect(start.split(taking: 4, of: arrow) == StolenSplit(clean: 3, stolen: 1))
        #expect(start.split(taking: 2, of: arrow) == StolenSplit(clean: 2, stolen: 0))
        #expect(start.split(taking: 0, of: arrow) == .none)
    }

    /// Removing more than is held fails and writes nothing, whichever flavour
    /// the shortfall is in.
    @Test func removingMoreThanIsHeldStillFails() throws {
        let start = try ReferenceInventoryState()
            .adding(arrow, count: 2, owner: owner, stolen: true)

        #expect(throws: InventoryError.self) {
            try start.removing(arrow, count: 3, owner: owner)
        }
    }

    /// Re-marking moves copies from honest to stolen without changing the
    /// total, which is what taking out of an owned container does.
    @Test func markingStolenMovesCopiesWithoutChangingTheTotal() throws {
        let start = try ReferenceInventoryState().adding(arrow, count: 5, owner: owner)

        let marked = start.markingStolen(arrow, count: 2)
        #expect(marked.count(of: arrow) == 5)
        #expect(marked.stolenCount(of: arrow) == 2)
        #expect(marked.count(of: arrow, stolen: false) == 3)
        // Nothing to mark is a no-op rather than a failure.
        #expect(marked.markingStolen(sword, count: 1) == marked)
        #expect(marked.markingStolen(arrow, count: 0) == marked)
    }

    // MARK: - Movement

    /// A transfer carries the split with it: hot goods stay hot on the other
    /// side.
    @Test func aTransferCarriesTheStolenSplit() throws {
        let harness = try InventoryHarness()
        try harness.runtime.add(arrow, count: 3, to: .player)
        try harness.runtime.add(arrow, count: 2, to: .player, stolen: true)

        try harness.runtime.transfer(arrow, count: 4, from: .player, to: harness.chest)

        #expect(harness.runtime.count(of: arrow, in: harness.chest) == 4)
        #expect(harness.runtime.stolenCount(of: arrow, in: harness.chest) == 1)
        #expect(harness.runtime.count(of: arrow, in: .player) == 1)
        #expect(harness.runtime.stolenCount(of: arrow, in: .player) == 1)
    }

    /// A transfer told to mark stolen marks the whole movement, which is what a
    /// take out of a container somebody else owns is.
    @Test func aTransferMayMarkTheWholeMovementStolen() throws {
        let harness = try InventoryHarness()
        try harness.runtime.add(sword, count: 2, to: harness.chest)

        try harness.runtime.transfer(
            sword, count: 2, from: harness.chest, to: .player, markingStolen: true
        )

        #expect(harness.runtime.stolenCount(of: sword, in: .player) == 2)
        #expect(harness.runtime.count(of: sword, in: harness.chest) == 0)
    }

    /// A barter carries each leg's own split, so selling hot goods hands the
    /// merchant hot goods and the gold that comes back is honest.
    @Test func anExchangeCarriesEachLegsOwnSplit() throws {
        let harness = try InventoryHarness()
        let gold = InventoryRuntime.vanillaGoldFormID
        try harness.runtime.add(sword, count: 1, to: .player, stolen: true)
        try harness.runtime.add(gold, count: 100, to: harness.chest)

        try harness.runtime.exchange(
            giving: (item: sword, amount: 1),
            taking: (item: gold, amount: 25),
            from: .player,
            to: harness.chest
        )

        #expect(harness.runtime.stolenCount(of: sword, in: harness.chest) == 1)
        #expect(harness.runtime.count(of: gold, in: .player) == 25)
        #expect(harness.runtime.stolenCount(of: gold, in: .player) == 0)
    }

    /// A conservation check across the pair: the totals do not move, whatever
    /// the split does.
    @Test func aTransferConservesTheTotalCount() throws {
        let harness = try InventoryHarness()
        try harness.runtime.add(arrow, count: 4, to: .player)
        try harness.runtime.add(arrow, count: 6, to: .player, stolen: true)

        try harness.runtime.transfer(arrow, count: 7, from: .player, to: harness.chest)

        let held = harness.runtime.count(of: arrow, in: .player)
        let stored = harness.runtime.count(of: arrow, in: harness.chest)
        #expect(held + stored == 10)
        #expect(
            harness.runtime.stolenCount(of: arrow, in: .player)
                + harness.runtime.stolenCount(of: arrow, in: harness.chest) == 6
        )
    }

    // MARK: - The lists

    /// One row per item, not per stack: two rows with the same name and FormID
    /// would be two identical-looking controls acting on the same items.
    @Test func theInventoryMenuShowsOneRowPerItemWithAStolenCount() throws {
        let inventory = try ReferenceInventoryState()
            .adding(arrow, count: 11, owner: owner)
            .adding(arrow, count: 1, owner: owner, stolen: true)
            .adding(sword, count: 1, owner: owner, stolen: true)

        let model = try InventoryMenuModel.build(
            inventory: inventory,
            items: InventoryBaselineFixture.resolver().items
        )

        let arrows = try #require(model.allEntries.first { $0.item == arrow })
        #expect(arrows.count == 12)
        #expect(arrows.stolenCount == 1)
        #expect(arrows.isStolen)
        #expect(model.allEntries.count { $0.item == arrow } == 1)

        let swords = try #require(model.allEntries.first { $0.item == sword })
        #expect(swords.count == 1)
        #expect(swords.stolenCount == 1)

        // The row line says how many of the row are hot, because the flag is
        // per copy.
        #expect(InventoryMenuSection.line(for: arrows).contains("[1 stolen]"))
        #expect(InventoryMenuSection.line(for: swords).contains("[stolen]"))
    }

    /// An inventory runtime over an empty baseline, plus one container to move
    /// things into.
    @MainActor
    private struct InventoryHarness {
        let runtime: InventoryRuntime
        let chest: InventoryHolder

        init() throws {
            runtime = try InventoryRuntime(
                store: WorldStateStore(),
                baselines: InventoryBaselineFixture.resolver()
            )
            // The empty container, so nothing arrives from a CNTO baseline and
            // every stack under test was put there by the suite.
            chest = InventoryHolder(
                key: .plugin(name: "base.esm", objectID: 0x710),
                owner: .container(base: InventoryBaselineFixture.emptyChest)
            )
        }
    }
}
