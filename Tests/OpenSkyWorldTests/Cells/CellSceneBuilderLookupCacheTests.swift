// The worldspace and exterior-cell lookups a builder caches across builds must
// answer like the uncached depth-first walk did.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import Testing

@Suite(.tags(.gpu))
struct CellSceneBuilderLookupCacheTests: CellSceneBuilderFixture {
    let dataURL: URL

    init() throws {
        dataURL = try Self.makeDataDirectory()
    }

    @Test(.enabled(if: Self.hasDevice)) func firstCellInWalkOrderWinsForADuplicateGrid() throws {
        let builder = try makeBuilder(extraWorldChildren: block(
            cellFormID: 0x50, editorID: "EarlierCell", grid: (6, -2)
        ))
        let world = try builder.worldChildrenGroup(editorID: "Tamriel", localized: false)
        for _ in 0 ..< 2 {
            let found = builder.findCell(in: world, gridX: 6, gridY: -2, localized: false)
            #expect(found?.cell.editorID == "EarlierCell")
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func findsEveryCellAfterOneWalk() throws {
        let builder = try makeBuilder(extraWorldChildren: block(
            cellFormID: 0x50, editorID: "OtherCell", grid: (-40, 33)
        ))
        let world = try builder.worldChildrenGroup(editorID: "Tamriel", localized: false)
        let other = builder.findCell(in: world, gridX: -40, gridY: 33, localized: false)
        let target = builder.findCell(in: world, gridX: 6, gridY: -2, localized: false)
        #expect(other?.formID == 0x50)
        #expect(target?.cell.editorID == "TestCell06")
        #expect(target?.children != nil)
        #expect(builder.findCell(in: world, gridX: 0, gridY: 0, localized: false) == nil)
    }

    @Test(.enabled(if: Self.hasDevice)) func persistentCellIsNotAnExteriorCell() throws {
        // The persistent CELL sits directly in the world children and carries XCLC (0,0).
        let persistent = ESMFixture.record("CELL", formID: 0x60, data: cellFields(
            editorID: "Persistent", grid: (0, 0), flags: 0, waterHeightBits: nil, waterType: nil
        ))
        let builder = try makeBuilder(extraWorldChildren: persistent)
        let world = try builder.worldChildrenGroup(editorID: "Tamriel", localized: false)
        #expect(builder.findCell(in: world, gridX: 0, gridY: 0, localized: false) == nil)
        #expect(builder.persistentCell(in: world, localized: false)?.formID == 0x60)
    }

    @Test(.enabled(if: Self.hasDevice)) func rebuildMatchesFirstBuild() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let device = try #require(Self.device)
        let builder = try makeBuilder(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
        ), device: device)
        let first = try builder.buildScene(worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2)
        let second = try builder.buildScene(worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2)
        #expect(second.summary.summaryLine == first.summary.summaryLine)
        #expect(second.renderScene.instanceCount == 1)
        #expect(throws: CellSceneError.worldspaceNotFound(editorID: "Nirn")) {
            _ = try builder.buildScene(worldspaceEditorID: "Nirn", gridX: 6, gridY: -2)
        }
    }

    private func makeBuilder(extraWorldChildren: Data) throws -> CellSceneBuilder {
        let device = try #require(Self.device)
        return try makeBuilder(
            pluginData: plugin(extraWorldChildren: extraWorldChildren), device: device
        )
    }

    private func block(cellFormID: UInt32, editorID: String, grid: (x: Int32, y: Int32)) -> Data {
        let cell = ESMFixture.record("CELL", formID: cellFormID, data: cellFields(
            editorID: editorID, grid: grid, flags: 0, waterHeightBits: nil, waterType: nil
        ))
        let subBlock = ESMFixture.exteriorBlock(
            x: Int16(grid.x >> 3), y: Int16(grid.y >> 3), groupType: 5, contents: cell
        )
        return ESMFixture.exteriorBlock(
            x: Int16(grid.x >> 5), y: Int16(grid.y >> 5), groupType: 4, contents: subBlock
        )
    }
}
