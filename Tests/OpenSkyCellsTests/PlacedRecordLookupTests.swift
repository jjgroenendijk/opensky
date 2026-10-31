// `Cell.Reset` flags a cell that is not loaded, so its place comes from the
// load order, not from the resident cells.

import Foundation
@testable import OpenSkyCells
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
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
}
