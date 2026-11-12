// An interior lit only by its lighting template, and the lamps it places. Layouts:
// UESP CELL and LGTM pages; docs/formats/esm-records.md. Synthetic plugin only.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyTagsTesting
import OpenSkyWorldTesting
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct CellSceneBuilderLightingTemplateTests: CellSceneBuilderFixture {
    let dataURL: URL
    private let room: UInt32 = 0x5000

    init() throws {
        dataURL = try Self.makeDataDirectory()
    }

    private func template(formID: UInt32) -> Data {
        ESMFixture.record("LGTM", formID: formID, data: ESMFixture.field(
            "EDID", ESMFixture.zstring("RoomTemplate")
        ) + ESMFixture.field("DATA", ESMFixture.cellLightingData(inherits: 0)))
    }

    private func buildRoom(templateID: UInt32) throws -> CellScene {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        var ltmp = Data()
        ltmp.appendUInt32(templateID)
        let device = try #require(Self.device)
        let builder = try makeBuilder(
            pluginData: plugin(
                statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif"),
                modelBaseRecords: ["LGTM": template(formID: 0x600)],
                interiorRecords: interiorCellGroup(
                    formID: room,
                    refs: refrRecord(formID: 0x300, base: 0x100),
                    cellFields: ESMFixture.field("LTMP", ltmp)
                )
            ),
            device: device
        )
        return try builder.interiorBuilder.buildInteriorScene(cellFormID: FormID(room))
    }

    @Test(.enabled(if: Self.hasDevice)) func aRoomWithoutItsOwnLightUsesTheTemplate() throws {
        let lighting = try #require(try buildRoom(templateID: 0x600).renderScene.lighting)
        #expect(lighting.ambientColor == SIMD3<Float>(10, 20, 30) / 255)
        #expect(lighting.fog != nil)
    }

    @Test(.enabled(if: Self.hasDevice)) func aMissingTemplateLeavesTheRoomUnlit() throws {
        #expect(try buildRoom(templateID: 0x601).renderScene.lighting == nil)
    }
}
