// The game's order of owners: the encounter zone answers before the cell, and the
// player needs only membership in an owning faction.

import Foundation
@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct OwnershipOrderTests {
    private static let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
    private static let shop = CellSceneLocation.interior(FormID(0x900))
    private static let zone = FormID(0x880)
    private static let plate = ReferenceKey.generated(41)

    /// An `ECZN` owned by the hold faction, rank -1.
    private static func zones() throws -> EncounterZoneStore {
        var data = Data()
        data.appendUInt32(CrimeFixture.Factions.hold)
        data.appendUInt32(0)
        data.append(contentsOf: [0xFF, 1, 0, 0])
        let file = try ESMFixture.plugin(records: [
            ESMFixture.record("ECZN", formID: zone.rawValue, data: ESMFixture.field("DATA", data))
        ])
        return EncounterZoneStore(plugins: [(CrimeFixture.pluginName, file)])
    }

    private static func coordinator(_ world: FakeCrimeSessionWorld) throws -> CrimeCoordinator {
        let data = try CrimeSessionData(
            runtime: CrimeFixture.runtime(),
            locations: CrimeFixture.locationStore(),
            pluginName: CrimeFixture.pluginName,
            encounterZones: zones()
        )
        world.references = FakeCrimeReferences(cell: shop)
        return CrimeCoordinator(world: world, data: data, witnesses: nil, storyEvents: nil)
    }

    @Test func anUnownedItemInAnOwnedZoneIsTheftToTake() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        #expect(coordinator.crimeOwner(of: Self.plate) == nil)

        world.zoneLinks[Self.plate] = Self.zone
        #expect(coordinator.crimeOwner(of: Self.plate)?.key == Self.hold)
        #expect(coordinator.ownershipVerdict(on: Self.plate).isTheft)
    }

    @Test func theZoneAnswersBeforeTheCell() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        world.cellOwners[Self.shop] = RecordOwnership(
            owner: FormID(CrimeFixture.Factions.shopkeepers)
        )
        world.zoneLinks[Self.plate] = Self.zone
        #expect(coordinator.crimeOwner(of: Self.plate)?.key == Self.hold)
    }

    /// A teleport door with no owner of its own takes the owner of the door it leads to.
    @Test func aDoorTakesTheOwnerOfItsFarDoor() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        let references = FakeCrimeReferences(cell: Self.shop)
        world.references = references
        var link = Data()
        link.appendUInt32(0x951)
        link.append(Data(count: 28))
        var owner = Data()
        owner.appendUInt32(CrimeFixture.Factions.hold)
        references.entries = try [
            Self.door(0x950, fields: ESMFixture.field("XTEL", link)),
            Self.door(0x951, fields: ESMFixture.field("XOWN", owner))
        ]
        #expect(coordinator.crimeOwner(of: references.entries[0].key)?.key == Self.hold)
    }

    private static func door(_ objectID: UInt32, fields: Data) throws -> RuntimeReferenceEntry {
        var base = Data()
        base.appendUInt32(0x700)
        let reference = try PlacedReference(record: ESMFixture.parseRecord(ESMFixture.record(
            "REFR",
            formID: objectID,
            data: ESMFixture.field("NAME", base) + ESMFixture.field("DATA", Data(count: 24))
                + fields
        )))
        return RuntimeReferenceEntry(
            key: .plugin(name: CrimeFixture.pluginName, objectID: objectID),
            formID: FormID(objectID),
            isPersistent: false,
            record: .reference(reference)
        )
    }

    @Test func thePlayerNeedsOnlyMembershipInAnOwningFaction() {
        let owner = ReferenceOwner.faction(Self.hold, requiredRank: 3)
        let memberships = CrimeFixture.state([(CrimeFixture.Factions.hold, 0)])
        var player = CrimeActor(memberships: memberships)
        #expect(!player.mayUse(owner))
        player.ignoresRequiredRank = true
        #expect(player.mayUse(owner))
        #expect(!CrimeActor(ignoresRank: true).mayUse(owner))
    }
}

extension CrimeActor {
    fileprivate init(ignoresRank: Bool) {
        self.init()
        ignoresRequiredRank = ignoresRank
    }
}
