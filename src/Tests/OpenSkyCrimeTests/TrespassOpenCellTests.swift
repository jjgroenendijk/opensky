// Who may be in a private cell: a cell its owner opened, and a friend of the owner.
// See docs/engine/crime.md#who-may-be-in-a-private-cell.

import Foundation
@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFactionsInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct TrespassOpenCellTests {
    private static let shop = CellSceneLocation.interior(FormID(0x900))
    private static let ownerBase: UInt32 = 0x710
    private static let ownerActor: UInt32 = 0x711

    private static func coordinator(
        _ world: FakeCrimeSessionWorld, store: WorldStateStore = WorldStateStore(),
        storyEvents: StoryEventRecorder? = nil
    ) throws -> CrimeCoordinator {
        let coordinator = try CrimeCoordinator(
            world: world,
            data: CrimeSessionData(
                runtime: CrimeFixture.runtime(store: store), locations: nil,
                pluginName: CrimeFixture.pluginName
            ),
            witnesses: nil, storyEvents: storyEvents
        )
        world.currentCellLocation = Self.shop
        world.references = FakeCrimeReferences(cell: Self.shop)
        return coordinator
    }

    @Test func aCellTheOwnerOpenedIsNoTrespassUntilItClosesAgain() throws {
        let world = FakeCrimeSessionWorld()
        world.cellOwners[Self.shop] = RecordOwnership(owner: FormID(CrimeFixture.Factions.hold))
        let recorder = StoryEventRecorder()
        let coordinator = try Self.coordinator(world, storyEvents: recorder)
        var opened = true
        coordinator.scriptedCellOpened = { _ in opened }
        #expect(coordinator.scriptedCellOpened?(.generated(1)) == true)
        coordinator.advanceTrespass(by: 0)
        #expect(!coordinator.isPlayerTrespassing)
        #expect(recorder.events("TRES").isEmpty)

        opened = false
        coordinator.advanceTrespass(by: 1)
        #expect(coordinator.isPlayerTrespassing)
        #expect(recorder.events("TRES").count == 1)

        opened = true
        coordinator.advanceTrespass(by: 1)
        #expect(!coordinator.isPlayerTrespassing)
    }

    @Test func aFriendOfTheOwnerMayStayInTheOwnersHome() throws {
        let store = WorldStateStore()
        let world = FakeCrimeSessionWorld()
        world.cellOwners[Self.shop] = RecordOwnership(owner: FormID(Self.ownerBase))
        let coordinator = try Self.coordinator(world, store: store)
        let references = FakeCrimeReferences(cell: Self.shop)
        let owner = try Self.actor(Self.ownerActor, base: Self.ownerBase)
        references.entries = [owner]
        world.references = references
        coordinator.advanceTrespass(by: 0)
        #expect(coordinator.isPlayerTrespassing)

        store.set(ActorRelationshipState().setting(1, toward: owner.key), for: .player, in: nil)
        coordinator.advanceTrespass(by: 1)
        #expect(!coordinator.isPlayerTrespassing)
    }

    private static func actor(_ objectID: UInt32, base: UInt32) throws -> RuntimeReferenceEntry {
        var name = Data()
        name.appendUInt32(base)
        let actor = try PlacedActor(record: ESMFixture.parseRecord(ESMFixture.record(
            "ACHR", formID: objectID,
            data: ESMFixture.field("NAME", name) + ESMFixture.field("DATA", Data(count: 24))
        )))
        return RuntimeReferenceEntry(
            key: .plugin(name: CrimeFixture.pluginName, objectID: objectID),
            formID: FormID(objectID), isPersistent: true, record: .actor(actor)
        )
    }
}
