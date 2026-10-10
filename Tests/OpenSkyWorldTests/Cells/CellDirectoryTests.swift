// A console-style teleport finds an interior by editor ID and enters through a
// door that leads in, even when a later plugin overrides the cell.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import Testing

struct CellDirectoryTests {
    private static let cell: UInt32 = 0x1234
    private static let outsideDoor: UInt32 = 0x500
    private let fixtures: CellSceneFixture

    init() throws {
        fixtures = try CellSceneFixture()
    }

    private func plugin(masters: [String], refs: Data) throws -> ESMFile {
        try ESMFile(data: ESMFixture.tes4(masters: masters)
            + ESMFixture.topGroup(
                "CELL", contents: fixtures.interiorCellGroup(formID: Self.cell, refs: refs)
            ))
    }

    @Test
    func anOverrideWithoutADoorKeepsTheMastersDoor() throws {
        let door = fixtures.refrRecord(
            formID: 0x210,
            base: 0x100,
            teleport: TeleportFixture(door: Self.outsideDoor, position: .zero, rotation: .zero)
        )
        let base = try plugin(masters: [], refs: door)
        let mod = try plugin(
            masters: ["Skyrim.esm"], refs: fixtures.refrRecord(formID: 0x0100_0800, base: 0x100)
        )
        let loadOrder = LoadOrderPlugins([("Skyrim.esm", base), ("Mod.esp", mod)])
        #expect(CellDirectory.find(editorID: "TestInterior", in: loadOrder)
            == .interior(cell: FormID(Self.cell), entryDoor: FormID(Self.outsideDoor)))
    }

    @Test
    func anInteriorWithNoDoorAnywhereHasNoEntry() throws {
        let base = try plugin(masters: [], refs: fixtures.refrRecord(formID: 0x210, base: 0x100))
        let loadOrder = LoadOrderPlugins([("Skyrim.esm", base)])
        #expect(CellDirectory.find(editorID: "TestInterior", in: loadOrder)
            == .interior(cell: FormID(Self.cell), entryDoor: nil))
    }
}
