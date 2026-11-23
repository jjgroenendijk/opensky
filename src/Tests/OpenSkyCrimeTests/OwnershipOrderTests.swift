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
