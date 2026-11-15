// `Cell.Reset` flags a cell that is not loaded, so its place comes from the
// load order, not from the resident cells.

import Foundation
@testable import OpenSkyCells
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldTesting
import Testing

struct PlacedRecordLookupTests {
    private let fixtures: CellSceneFixture

    init() throws {
        fixtures = try CellSceneFixture()
    }

    @Test
    func aCellNamesItsGridOrItsInterior() throws {
        let exterior = try ESMFile(data: fixtures.plugin(grid: (7, -8)))
        let interior = try ESMFile(data: ESMFixture.tes4(masters: ["Skyrim.esm"])
            + ESMFixture.topGroup("CELL", contents: fixtures.interiorCellGroup(
                formID: 0x1234, refs: fixtures.refrRecord(formID: 0x210, base: 0x100)
            )))
        let lookup = PlacedRecordLookup(index: LoadOrderRecordIndex(
            plugins: [("Skyrim.esm", exterior), ("Mod.esp", interior)]
        ))
        #expect(lookup.location(ofCell: FormID(0x2B)) == .exterior(CellCoordinate(x: 7, y: -8)))
        #expect(lookup.location(ofCell: FormID(0x1234)) == .interior(FormID(0x1234)))
        #expect(lookup.location(ofCell: FormID(0x210)) == nil)
        #expect(lookup.location(ofCell: FormID(0x9999)) == nil)
    }

    /// Each side of a load door stores the other side's arrival, so the spot behind a door
    /// comes from its partner's `XTEL`.
    @Test
    func aDoorLeadsToTheArrivalItsPartnerStores() throws {
        let arrival = SIMD3<Float>(10, 20, 30)
        let refs = fixtures.refrRecord(
            formID: 0x210, base: 0x100,
            teleport: TeleportFixture(door: 0x211, position: SIMD3(1, 2, 3), rotation: .zero)
        ) + fixtures.refrRecord(
            formID: 0x211, base: 0x100,
            teleport: TeleportFixture(door: 0x210, position: arrival, rotation: .zero)
        ) + fixtures.refrRecord(formID: 0x212, base: 0x101)
        let plugin = try ESMFile(data: ESMFixture.tes4(masters: [])
            + ESMFixture.topGroup(
                "STAT",
                contents: ESMFixture.record("STAT", formID: 0x101, data: Data())
            )
            + ESMFixture.topGroup(
                "CELL",
                contents: fixtures.interiorCellGroup(formID: 0x1234, refs: refs)
            ))
        let index = LoadOrderRecordIndex(plugins: [("Skyrim.esm", plugin)])
        let lookup = PlacedRecordLookup(index: index)
        let door = try #require(index.record(withFormID: FormID(0x210)))
            .decode(PlacedReference.init(record:))
        let plain = try #require(index.record(withFormID: FormID(0x212)))
            .decode(PlacedReference.init(record:))
        #expect(lookup.arrival(through: door)?.position == arrival)
        #expect(lookup.arrival(through: plain) == nil)
        #expect(lookup.recordType(ofBase: FormID(0x101)) == "STAT")
        #expect(lookup.recordType(ofBase: FormID(0x9999)) == nil)
    }
}
