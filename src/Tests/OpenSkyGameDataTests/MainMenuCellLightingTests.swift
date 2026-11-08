// The main menu's light comes from the cell the DOBJ `MMCL` default object names,
// and from that cell's lighting template.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct MainMenuCellLightingTests {
    @Test func theMMCLCellAndItsTemplateGiveTheLight() throws {
        var templateData = ESMFixture.cellLightingData(inherits: 0)
        templateData.replaceSubrange(0 ..< 4, with: [200, 201, 202, 0])
        let file = try ESMFixture.plugin(records: [
            defaultObjects(cell: 0x20),
            ESMFixture.record("CELL", formID: 0x20, data: ESMFixture.field(
                "XCLL", ESMFixture.cellLightingData(inherits: 0x0001)
            ) + ESMFixture.field("LTMP", ESMFixture.words([0x30]))),
            ESMFixture.record("LGTM", formID: 0x30, data: ESMFixture.field("DATA", templateData))
        ])
        let loadOrder = LoadOrderPlugins([("Skyrim.esm", file)])
        let lighting = try #require(MainMenuCellLighting(
            loadOrder: loadOrder,
            defaultObjects: DefaultObjectStore(plugins: loadOrder.files)
        ))
        #expect(lighting.cell?.inherits.contains(.ambientColor) == true)
        #expect(lighting.template?.ambientColor == SIMD3<Float>(200, 201, 202) / 255)
    }

    @Test func noMMCLEntryGivesNoLight() throws {
        let file = try ESMFixture.plugin(records: [defaultObjects(cell: nil)])
        let loadOrder = LoadOrderPlugins([("Skyrim.esm", file)])
        #expect(MainMenuCellLighting(
            loadOrder: loadOrder,
            defaultObjects: DefaultObjectStore(plugins: loadOrder.files)
        ) == nil)
    }

    private func defaultObjects(cell: UInt32?) -> Data {
        var entries = Data("GOLD".utf8)
        entries.appendUInt32(0x0F)
        if let cell {
            entries.append(contentsOf: Data(MainMenuCellLighting.defaultObjectTag.utf8))
            entries.appendUInt32(cell)
        }
        return ESMFixture.record("DOBJ", formID: 0x31, data: ESMFixture.field("DNAM", entries))
    }
}
