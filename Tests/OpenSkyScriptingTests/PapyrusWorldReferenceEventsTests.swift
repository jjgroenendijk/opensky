// Open, close, lock, and pick-up events read from the world-state journal, over a
// synthetic lever whose base object is 0x100.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyInventoryInterface
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusWorldReferenceEventsTests {
    private typealias Fixture = PapyrusNativeReferenceFixture
    private static let leverBase = FormID(0x100)

    private static func fixture() throws -> Fixture {
        let fixture = try Fixture.make(events: [
            "OnOpen", "OnClose", "OnLockStateChanged", "OnContainerChanged"
        ].map { ($0, PapyrusWorldFixture.probeBody(note: $0.lowercased())) })
        fixture.session.bridge.queueReferenceStateEvents()
        return fixture
    }

    private static func run(_ fixture: Fixture) -> [String] {
        let before = fixture.session.dispatch.notes.count
        fixture.session.bridge.queueReferenceStateEvents()
        PapyrusWorldFixture.drain(fixture.session.world)
        return Array(fixture.session.dispatch.notes.dropFirst(before))
    }

    private static func setOpen(_ fixture: Fixture, _ isOpen: Bool) {
        _ = fixture.session.worldState.set(
            ReferenceActivationState(activationCount: 1, isOpen: isOpen, lastActivator: .player),
            for: fixture.key, in: nil
        )
    }

    @Test func openingAndClosingQueueTheirEvents() throws {
        let fixture = try Self.fixture()
        Self.setOpen(fixture, true)
        #expect(Self.run(fixture) == ["onopen"])
        Self.setOpen(fixture, true)
        #expect(Self.run(fixture).isEmpty)
        Self.setOpen(fixture, false)
        #expect(Self.run(fixture) == ["onclose"])
    }

    @Test func aLockChangeQueuesOneEvent() throws {
        let fixture = try Self.fixture()
        let locked = ReferenceLockState(isLocked: true, level: 25, key: nil)
        _ = fixture.session.worldState.set(locked, for: fixture.key, in: nil)
        #expect(Self.run(fixture) == ["onlockstatechanged"])
        var raised = locked
        raised.level = 50
        _ = fixture.session.worldState.set(raised, for: fixture.key, in: nil)
        #expect(Self.run(fixture).isEmpty)
    }

    @Test func aTakeTellsTheReferenceItsNewContainer() throws {
        let fixture = try Self.fixture()
        let carried = ReferenceInventoryState(stacks: [InventoryStack(
            item: Self.leverBase,
            count: 1
        )])
        _ = fixture.session.worldState.set(carried, for: .player, in: nil)
        _ = fixture.session.worldState.set(
            ReferenceDeletionState.deleted,
            for: fixture.key,
            in: nil
        )
        #expect(Self.run(fixture) == ["oncontainerchanged"])
    }

    @Test func aDeletionWithoutATakeSendsNothing() throws {
        let fixture = try Self.fixture()
        _ = fixture.session.worldState.set(
            ReferenceDeletionState.deleted,
            for: fixture.key,
            in: nil
        )
        #expect(Self.run(fixture).isEmpty)
    }
}
