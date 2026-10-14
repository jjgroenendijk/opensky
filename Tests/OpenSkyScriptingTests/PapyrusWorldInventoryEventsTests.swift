// Item and equip events read from the world-state journal, and the inventory event
// filters, over a synthetic lever that holds items.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyInventoryInterface
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusWorldInventoryEventsTests {
    private typealias Fixture = PapyrusNativeReferenceFixture
    private static let ingot: UInt32 = 0x0010
    private static let sword: UInt32 = 0x0011

    private static func fixture() throws -> Fixture {
        try Fixture.make(events: [
            "OnItemAdded", "OnItemRemoved", "OnObjectEquipped", "OnObjectUnequipped"
        ].map { ($0, PapyrusWorldFixture.probeBody(note: $0.lowercased())) })
    }

    private static func write(
        _ fixture: Fixture, _ stacks: [(UInt32, Int32)], equipped: [UInt32] = []
    ) {
        let state = ReferenceInventoryState(
            stacks: stacks.map { InventoryStack(item: FormID($0.0), count: $0.1) },
            equipped: equipped.map { FormID($0) }
        )
        _ = fixture.session.worldState.set(state, for: fixture.key, in: nil)
    }

    private static func run(_ fixture: Fixture) -> [String] {
        let before = fixture.session.dispatch.notes.count
        fixture.session.bridge.queueInventoryEvents()
        PapyrusWorldFixture.drain(fixture.session.world)
        return Array(fixture.session.dispatch.notes.dropFirst(before))
    }

    @Test func countAndEquipChangesQueueTheirEvents() throws {
        let fixture = try Self.fixture()
        Self.write(fixture, [(Self.ingot, 2)])
        // The first read only sets the cursor.
        #expect(Self.run(fixture).isEmpty)

        Self.write(fixture, [(Self.ingot, 3), (Self.sword, 1)], equipped: [Self.sword])
        #expect(Self.run(fixture).sorted() == ["onitemadded", "onitemadded", "onobjectequipped"])

        Self.write(fixture, [(Self.sword, 1)])
        #expect(Self.run(fixture) == ["onitemremoved", "onobjectunequipped"])
        #expect(Self.run(fixture).isEmpty)
    }

    @Test func aFilterLetsOnlyItsItemsThrough() throws {
        let fixture = try Self.fixture()
        Self.write(fixture, [])
        _ = Self.run(fixture)
        #expect(fixture.call(
            "AddInventoryEventFilter", arguments: [.object(fixture.handle(Self.sword))]
        ) == .returned(.none))

        Self.write(fixture, [(Self.ingot, 1), (Self.sword, 1)])
        #expect(Self.run(fixture) == ["onitemadded"])

        _ = fixture.call("RemoveAllInventoryEventFilters")
        Self.write(fixture, [(Self.ingot, 2), (Self.sword, 1)])
        #expect(Self.run(fixture) == ["onitemadded"])
        Self.write(fixture, [(Self.ingot, 3), (Self.sword, 2)])
        #expect(Self.run(fixture).count == 2)
    }

    @Test func aCombatStateChangeQueuesOnce() throws {
        let fixture = try Fixture.make(events: [
            ("OnCombatStateChanged", PapyrusWorldFixture.probeBody(note: "combat"))
        ])
        let combat = FakeCombat()
        fixture.session.bridge.combatRuntime = { combat }
        let bridge = fixture.session.bridge
        #expect(bridge.queueCombatStateEvents() == 0)
        combat.activity = .fighting
        #expect(bridge.queueCombatStateEvents() == 1)
        #expect(bridge.queueCombatStateEvents() == 0)
        combat.activity = .notFighting
        #expect(bridge.queueCombatStateEvents() == 1)
        PapyrusWorldFixture.drain(fixture.session.world)
        #expect(fixture.session.dispatch.notes == ["combat", "combat"])
    }

    @Test func aLoadIsNotReadAsItemMoves() throws {
        let fixture = try Self.fixture()
        _ = Self.run(fixture)
        Self.write(fixture, [(Self.ingot, 5)])
        fixture.session.bridge.skipInventoryJournal()
        #expect(Self.run(fixture).isEmpty)
    }
}

private final class FakeCombat: CombatControlling {
    var activity = ActorCombatActivity.notFighting

    func activity(of _: ReferenceKey) -> ActorCombatActivity {
        activity
    }

    func startCombat(_: ReferenceKey, with _: ReferenceKey) -> Bool {
        false
    }

    func stopCombat(_: ReferenceKey) -> Bool {
        false
    }
}
