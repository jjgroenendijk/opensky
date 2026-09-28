// ReferenceInventoryState unit tests (issue #176): the stack invariants, the
// arithmetic that mutations are built from, and the equipped set.
//
// The value type is tested apart from `InventoryRuntime` because the
// conservation guarantees the runtime advertises rest on this arithmetic being
// total: an operation that cannot succeed must produce no value at all, which
// is what lets the runtime compute both sides of a transfer before writing
// either.

import Foundation
@testable import opensky
import Testing

struct InventoryComponentTests {
    private let owner = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0BAD)
    private let gold = FormID(0x0000_000F)
    private let sword = FormID(0x0001_2EB7)
    private let lockpick = FormID(0x00000A)

    // MARK: - Invariants

    @Test func stacksAreSortedByFormIDRegardlessOfInputOrder() {
        let ascending = ReferenceInventoryState(stacks: [
            InventoryStack(item: lockpick, count: 1),
            InventoryStack(item: gold, count: 2),
            InventoryStack(item: sword, count: 3)
        ])
        let descending = ReferenceInventoryState(stacks: [
            InventoryStack(item: sword, count: 3),
            InventoryStack(item: gold, count: 2),
            InventoryStack(item: lockpick, count: 1)
        ])
        #expect(ascending.stacks.map(\.item) == [lockpick, gold, sword])
        #expect(ascending == descending)
    }

    @Test func duplicateStacksMergeAndNonPositiveCountsDropOut() {
        let inventory = ReferenceInventoryState(stacks: [
            InventoryStack(item: gold, count: 30),
            InventoryStack(item: gold, count: 12),
            InventoryStack(item: sword, count: 0),
            InventoryStack(item: lockpick, count: -4)
        ])
        #expect(inventory.stacks.count == 1)
        #expect(inventory.count(of: gold) == 42)
        #expect(inventory.count(of: sword) == 0)
        #expect(inventory.count(of: lockpick) == 0)
    }

    /// The decoder path: a corrupt save whose two stacks of the same item add
    /// past `Int32` saturates rather than trapping or failing the load.
    @Test func mergingSaturatesInsteadOfOverflowing() {
        let inventory = ReferenceInventoryState(stacks: [
            InventoryStack(item: gold, count: .max),
            InventoryStack(item: gold, count: 100)
        ])
        #expect(inventory.count(of: gold) == Int32.max)
    }

    @Test func equippedSetIsSortedAndDeduplicated() {
        let inventory = ReferenceInventoryState(
            stacks: [],
            equipped: [sword, gold, sword, lockpick]
        )
        #expect(inventory.equipped == [lockpick, gold, sword])
    }

    @Test func emptyInventoryHoldsNothing() {
        #expect(ReferenceInventoryState.empty.isEmpty)
        #expect(ReferenceInventoryState.empty.totalCount == 0)
        #expect(ReferenceInventoryState.empty.count(of: gold) == 0)
    }

    // MARK: - Erasure

    @Test func erasureRoundTripsAndRejectsOtherKinds() {
        let inventory = ReferenceInventoryState(stacks: [
            InventoryStack(item: gold, count: 5)
        ])
        #expect(ReferenceInventoryState.componentKind == .inventory)
        #expect(inventory.erased.kind == .inventory)
        #expect(ReferenceInventoryState(erased: inventory.erased) == inventory)
        #expect(ReferenceInventoryState(erased: ReferenceEnableState.disabled.erased) == nil)
        #expect(ReferenceEnableState(erased: inventory.erased) == nil)
    }

    // MARK: - Arithmetic

    @Test func addingCreatesAndGrowsAStack() throws {
        let empty = ReferenceInventoryState.empty
        let one = try empty.adding(gold, count: 10, owner: owner)
        let two = try one.adding(gold, count: 15, owner: owner)
        #expect(one.count(of: gold) == 10)
        #expect(two.count(of: gold) == 25)
        #expect(two.stacks.count == 1)
        // The source value is untouched: every operation returns a new state.
        #expect(empty.isEmpty)
    }

    @Test func addingKeepsFormIDOrderWhenTheNewStackSortsFirst() throws {
        let inventory = try ReferenceInventoryState(stacks: [
            InventoryStack(item: sword, count: 1)
        ]).adding(gold, count: 1, owner: owner)
        #expect(inventory.stacks.map(\.item) == [gold, sword])
    }

    @Test func removingDropsTheStackWhenItReachesZero() throws {
        let inventory = try ReferenceInventoryState(stacks: [
            InventoryStack(item: gold, count: 3),
            InventoryStack(item: sword, count: 1)
        ]).removing(gold, count: 3, owner: owner)
        #expect(inventory.count(of: gold) == 0)
        #expect(inventory.stacks.map(\.item) == [sword])
    }

    @Test func removingMoreThanIsHeldFailsInsteadOfClamping() {
        let inventory = ReferenceInventoryState(stacks: [
            InventoryStack(item: gold, count: 3)
        ])
        #expect(throws: InventoryError.insufficientCount(
            item: gold, owner: owner, requested: 4, available: 3
        )) {
            try inventory.removing(gold, count: 4, owner: owner)
        }
        #expect(throws: InventoryError.insufficientCount(
            item: sword, owner: owner, requested: 1, available: 0
        )) {
            try inventory.removing(sword, count: 1, owner: owner)
        }
    }

    @Test func nonPositiveCountsAreRefusedOnBothSides() {
        let inventory = ReferenceInventoryState(stacks: [
            InventoryStack(item: gold, count: 3)
        ])
        #expect(throws: InventoryError.nonPositiveCount(0)) {
            try inventory.adding(gold, count: 0, owner: owner)
        }
        #expect(throws: InventoryError.nonPositiveCount(-2)) {
            try inventory.removing(gold, count: -2, owner: owner)
        }
    }

    @Test func addingPastInt32MaxIsAnOverflowFailure() {
        let inventory = ReferenceInventoryState(stacks: [
            InventoryStack(item: gold, count: Int32.max - 1)
        ])
        #expect(throws: InventoryError.countOverflow(item: gold, owner: owner)) {
            try inventory.adding(gold, count: 2, owner: owner)
        }
        #expect(throws: Never.self) {
            try inventory.adding(gold, count: 1, owner: owner)
        }
    }

    @Test func totalCountSumsPastASingleStacksRange() {
        let inventory = ReferenceInventoryState(stacks: [
            InventoryStack(item: gold, count: .max),
            InventoryStack(item: sword, count: .max)
        ])
        #expect(inventory.totalCount == Int(Int32.max) * 2)
    }

    // MARK: - Equipped set

    @Test func equippingAndUnequippingAreIdempotent() {
        let base = ReferenceInventoryState(stacks: [InventoryStack(item: sword, count: 1)])
        let equipped = base.equipping(sword).equipping(sword)
        #expect(equipped.equipped == [sword])
        #expect(equipped.isEquipped(sword))
        let bare = equipped.unequipping(sword).unequipping(sword)
        #expect(bare.equipped.isEmpty)
        #expect(bare.isEquipped(sword) == false)
        // Equipping never touches the stacks.
        #expect(equipped.count(of: sword) == 1)
    }

    @Test func settingTheEquippedSetReplacesItWholesale() {
        let inventory = ReferenceInventoryState(
            stacks: [InventoryStack(item: gold, count: 1)],
            equipped: [sword]
        ).settingEquipped([lockpick, gold, lockpick])
        #expect(inventory.equipped == [lockpick, gold])
        #expect(inventory.count(of: gold) == 1)
    }
}
