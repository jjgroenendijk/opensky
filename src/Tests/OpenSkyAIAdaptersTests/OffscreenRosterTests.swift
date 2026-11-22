// Where an unloaded actor stands, whether a place is loaded, and which loaded door leads out
// of a house. Synthetic records only.

import Foundation
import OpenSkyAIAdapters
import OpenSkyAIPackages
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

struct OffscreenRosterTests {
    private static let house = CellSceneLocation.interior(FormID(0x900))
    private static let square = CellSceneLocation.exterior(CellCoordinate(x: 40, y: -24))

    private static func resident() throws -> PluginPlacement {
        try PluginPlacement(
            entry: PackageRuntimeFixture.residentActor(0x500, base: 0x600), home: house
        )
    }

    @Test func anActorStandsWhereItsDeltasPutIt() throws {
        let plugin = try Self.resident()
        let key = PackageRuntimeFixture.key(0x500)
        let home = try #require(OffscreenRoster.actor(key, plugin: plugin, delta: nil))
        #expect(home.base == FormID(0x600))
        #expect(home.place.location == Self.house)
        #expect(home.place.worldspace == nil)

        let moved = ReferenceStateDelta(components: [
            .relocation: ReferenceRelocation(location: Self.square, worldspace: "RiftenWorld")
                .erased,
            .transform: ReferenceTransformOverride(position: SIMD3(5, 6, 7)).erased
        ])
        let away = try #require(OffscreenRoster.actor(key, plugin: plugin, delta: moved))
        #expect(away.place.location == Self.square)
        #expect(away.place.worldspace == "RiftenWorld")
        #expect(away.place.point == SIMD3(5, 6, 7))

        let disabled = ReferenceStateDelta(components: [
            .enableState: ReferenceEnableState.disabled.erased
        ])
        #expect(OffscreenRoster.actor(key, plugin: plugin, delta: disabled) == nil)
    }

    @Test func theRosterListsEachPersistentActorOnce() throws {
        let door = try #require(Self.door(leadingTo: 0x901).placedReference)
        let guardOne = PackageRuntimeFixture.key(0x500)
        let guardTwo = PackageRuntimeFixture.key(0x501)
        let listed = PackageRuntimeFixture.key(0x502)
        let base = PackageRuntimeFixture.key(0x600)
        let placements = try [0x501, 0x500].map { id in
            let actor = try #require(
                PackageRuntimeFixture.residentActor(UInt32(id), base: 0x600).placedActor
            )
            return PersistentPlacement(
                key: PackageRuntimeFixture.key(UInt32(id)), formID: actor.formID,
                record: .actor(actor), actorBase: base
            )
        } + [PersistentPlacement(
            key: PackageRuntimeFixture.key(0x700), formID: door.formID,
            record: .reference(door), actorBase: nil
        )]
        let keys = OffscreenRoster.keys(
            placements: placements, unique: [base: listed, .player: .player]
        )
        #expect(keys == [guardOne, guardTwo, listed])
    }

    @Test func aPlacedObjectIsNoActor() throws {
        let door = try Self.door(leadingTo: 0x901)
        let plugin = PluginPlacement(entry: door, home: Self.square, worldspace: "RiftenWorld")
        #expect(OffscreenRoster.actor(door.key, plugin: plugin, delta: nil) == nil)
        let place = OffscreenRoster.editorPlace(of: plugin, radius: 300)
        #expect(place.radius == 300)
        #expect(place.worldspace == "RiftenWorld")
    }

    @Test func anExteriorIsLoadedOnlyInTheResidentWorldspace() {
        let stall = OffscreenPlace(location: Self.square, worldspace: "RiftenWorld", point: .zero)
        let resident: Set<CellSceneLocation> = [Self.square, Self.house]
        #expect(OffscreenRoster.isLoaded(stall, resident: resident, worldspace: "riftenworld"))
        #expect(!OffscreenRoster.isLoaded(stall, resident: resident, worldspace: "Tamriel"))
        #expect(!OffscreenRoster.isLoaded(stall, resident: resident, worldspace: nil))
        #expect(!OffscreenRoster.isLoaded(stall, resident: [], worldspace: "RiftenWorld"))
        let room = OffscreenPlace(location: Self.house, worldspace: nil, point: .zero)
        #expect(OffscreenRoster.isLoaded(room, resident: resident, worldspace: nil))
    }

    @Test func theExitIsInFrontOfTheLoadedDoorIntoTheHouse() throws {
        let other = try Self.door(leadingTo: 0x902)
        let front = try Self.door(leadingTo: 0x901)
        let doors = OffscreenRoster.Doors(
            entries: [other, front],
            interiorCell: { $0 == FormID(0x901) ? FormID(0x900) : FormID(0x903) },
            arrival: { _ in PlacedReference.Placement(position: SIMD3(1, 2, 3), rotation: .zero) },
            location: { _ in Self.square },
            worldspace: "RiftenWorld"
        )
        let exit = try #require(OffscreenRoster.exit(from: FormID(0x900), through: doors))
        #expect(exit.location == Self.square)
        #expect(exit.worldspace == "RiftenWorld")
        #expect(exit.point == SIMD3(1, 2, 3))
        #expect(OffscreenRoster.exit(from: FormID(0x904), through: doors) == nil)
    }

    /// A load door REFR whose `XTEL` names the door on the other side.
    private static func door(leadingTo inside: UInt32) throws -> RuntimeReferenceEntry {
        var xtel = Data()
        xtel.appendUInt32(inside)
        for _ in 0 ..< 6 {
            xtel.appendFloat32(0)
        }
        xtel.appendUInt32(0)
        let fields = ESMFixture.field("NAME", PackageRuntimeFixture.formIDData(0x800))
            + ESMFixture.field("DATA", Data(count: 24)) + ESMFixture.field("XTEL", xtel)
        let reference = try PlacedReference(record: ESMFixture.parseRecord(
            ESMFixture.record("REFR", formID: inside + 0x100, data: fields)
        ))
        return RuntimeReferenceEntry(
            key: PackageRuntimeFixture.key(inside + 0x100), formID: FormID(inside + 0x100),
            isPersistent: true, record: .reference(reference)
        )
    }
}
