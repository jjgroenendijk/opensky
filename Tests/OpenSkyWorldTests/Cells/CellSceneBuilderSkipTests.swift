// Malformed records in a cell build are counted in `skippedRecords`, not dropped
// without a trace. Synthetic plugin fixtures only.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import Testing

extension CellSceneBuilderTests {
    @Test(.enabled(if: Self.hasDevice)) func countsMalformedBaseRecordOnce() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let bytes = plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
                + ESMFixture.malformedRecord("STAT", formID: 0x101)
        )
        let device = try #require(Self.device)
        let builder = try makeBuilder(pluginData: bytes, device: device)
        let first = try builder.buildScene(worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2)
        let second = try builder.buildScene(worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2)

        #expect(first.summary.drawnRefCount == 1)
        #expect(first.summary.skippedRecords.count(of: "STAT") == 1)
        #expect(first.summary.skippedRecords.byType["STAT"]?.firstError.contains("XXXX") == true)
        #expect(first.summary.summaryLine.hasSuffix(", 1 malformed records"))
        #expect(second.summary.skippedRecords.total == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func countsMalformedCellWhileSearching() throws {
        let bytes = plugin(extraWorldChildren: ESMFixture.exteriorBlock(
            x: 0, y: 0, groupType: 4, contents: ESMFixture.exteriorBlock(
                x: 0, y: 0, groupType: 5, contents: ESMFixture.malformedRecord("CELL", formID: 0x60)
            )
        ))
        let scene = try build(pluginData: bytes)

        #expect(scene.summary.skippedRecords.count(of: "CELL") == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func countsTruncatedBlockWhileSearching() throws {
        let bytes = plugin(extraWorldChildren: ESMFixture.exteriorBlock(
            x: 0, y: 0, groupType: 4, contents: Data(count: 10)
        ))
        let scene = try build(pluginData: bytes)

        #expect(scene.summary.skippedRecords.count(of: "GRUP") == 1)
    }

    @Test func modelCatalogCountsTruncatedBlock() throws {
        let bytes = plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100),
            extraWorldChildren: ESMFixture.exteriorBlock(
                x: 0, y: 0, groupType: 4, contents: Data(count: 10)
            )
        )
        let models = try ExteriorCellModelCatalog(file: ESMFile(data: bytes))
            .models(worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2)

        #expect(models.skippedRecords.count(of: "GRUP") == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func malformedDoorReferenceThrowsATypedError() throws {
        let bytes = plugin(interiorRecords: interiorCellGroup(
            formID: 0x0001_38CA, refs: ESMFixture.malformedRecord("REFR", formID: 0x300)
        ))
        let device = try #require(Self.device)
        let builder = try makeBuilder(pluginData: bytes, device: device)

        #expect {
            _ = try builder.buildDoorTransition(from: FormID(0x300), worldspaceEditorID: "Tamriel")
        } throws: { error in
            guard case let .malformedRecord(type, formID, reason) = error as? CellSceneError else {
                return false
            }
            return type == "REFR" && formID == FormID(0x300) && reason.contains("XXXX")
        }
    }

    @Test func modelCatalogCountsMalformedRecords() throws {
        let bytes = plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100)
                + ESMFixture.malformedRecord("REFR", formID: 0x201),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
                + ESMFixture.malformedRecord("STAT", formID: 0x101)
        )
        let models = try ExteriorCellModelCatalog(file: ESMFile(data: bytes))
            .models(worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2)

        #expect(models.paths == ["meshes\\arch\\wall.nif"])
        #expect(models.skippedRecords.count(of: "STAT") == 1)
        #expect(models.skippedRecords.count(of: "REFR") == 1)
    }
}
