// Container transfer session tests (issue #177, roadmap item 12.1.3): listing
// a container's effective contents, moving items both ways, and the open-state
// bookkeeping a menu will later sit on top of.
//
// Split from `WorldItemRuntimeTests`, whose fixtures it reuses, so both suites
// stay inside the strict-lint type-length cap.

import Foundation
@testable import opensky
import Testing

@MainActor
struct ContainerSessionTests {
    private typealias Fixture = InventoryBaselineFixture
    private typealias Parent = WorldItemRuntimeTests

    private struct Opened {
        let harness: Parent.Harness
        let session: ContainerSession
    }

    private func openChest() throws -> Opened {
        let harness = try Parent.standardHarness()
        return try Opened(
            harness: harness,
            session: harness.runtime.openContainer(Parent.interaction(
                reference: Parent.chestReference, base: Fixture.chest, action: .search
            ))
        )
    }

    @Test func openingAContainerRecordsItOpenAndListsItsBaseline() throws {
        let opened = try openChest()
        // The fixture chest holds three lockpicks, one gold and a leveled entry
        // that resolves to one iron sword.
        #expect(opened.session.totalCount == 5)
        #expect(opened.session.isOpen)

        opened.session.close()
        #expect(opened.session.isOpen == false)
        // Closing twice writes once: the second call already has what it wants.
        let sequence = opened.harness.store.nextJournalSequence
        opened.session.close()
        #expect(opened.harness.store.nextJournalSequence == sequence)
    }

    @Test func openingSomethingThatIsNotAContainerFails() throws {
        let harness = try Parent.standardHarness()
        #expect(throws: WorldItemError.notAContainer(Parent.looseItem)) {
            try harness.runtime.openContainer(Parent.interaction(
                reference: Parent.looseItem, base: Fixture.lockpick, action: .take
            ))
        }
    }

    @Test func takeAllConservesTheTotalCount() throws {
        let opened = try openChest()
        let before = opened.session.totalCount
        let moved = try opened.session.takeAll()

        #expect(opened.session.isEmpty)
        #expect(moved.reduce(0) { $0 + Int($1.count) } == before)
        let carried = opened.harness.runtime.inventory.inventory(of: .player)
        #expect(carried.totalCount == before)
        #expect(carried.count(of: Fixture.lockpick) == 3)
        #expect(carried.count(of: Fixture.gold) == 1)
    }

    @Test func depositMovesItemsBackAndConservesTheTotal() throws {
        let opened = try openChest()
        let total = opened.session.totalCount
        try opened.session.take(Fixture.lockpick, count: 2)
        try opened.session.deposit(Fixture.lockpick, count: 1)

        #expect(opened.session.totalCount == total - 1)
        let carried = opened.harness.runtime.inventory.count(of: Fixture.lockpick, in: .player)
        #expect(carried == 1)
    }

    /// Taking more than the container holds writes nothing at all, so the two
    /// inventories still sum to what they started with.
    @Test func overTakeFromAContainerWritesNothing() throws {
        let opened = try openChest()
        let total = opened.session.totalCount
        #expect(throws: (any Error).self) {
            try opened.session.take(Fixture.lockpick, count: 99)
        }
        #expect(opened.session.totalCount == total)
        #expect(opened.harness.runtime.inventory.inventory(of: .player).isEmpty)
    }
}
