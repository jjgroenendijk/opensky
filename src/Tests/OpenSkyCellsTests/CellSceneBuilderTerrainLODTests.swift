// Without LOD files and without LAND records, the terrain LOD part falls back to the
// vanilla brightness and generates no terrain block. A water flow map is found only
// when its loose file exists. Synthetic plugin only.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsTesting
import OpenSkyRenderCore
import OpenSkyTagsTesting
@testable import OpenSkyTerrain
import OpenSkyWorldTesting
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct CellSceneBuilderTerrainLODTests: CellSceneBuilderFixture {
    let dataURL: URL

    init() throws {
        dataURL = try Self.makeDataDirectory()
    }

    private func makeBuilder() throws -> CellSceneBuilder {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let device = try #require(Self.device)
        return try makeBuilder(
            pluginData: plugin(
                temporaryRefs: refrRecord(formID: 0x200, base: 0x100),
                statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
            ),
            device: device
        )
    }

    @Test(.enabled(if: Self.hasDevice)) func aWorldWithoutLODFilesKeepsTheVanillaCurve() throws {
        let terrain = try makeBuilder().terrainBuilder
        #expect(terrain.terrainLOD.terrainLODBrightness(lodWorldspace: "Tamriel") == .vanilla)
        #expect(terrain.terrainLOD.terrainLODBrightness(lodWorldspace: "tamriel") == .vanilla)
    }

    @Test(.enabled(if: Self.hasDevice)) func aWorldIsItsOwnLODWorld() throws {
        let terrain = try makeBuilder().terrainBuilder
        #expect(terrain.distantLOD.lodWorldspace(of: "Tamriel") == "Tamriel")
    }

    @Test(.enabled(if: Self.hasDevice)) func aBlockWithoutLandGeneratesNoTerrain() throws {
        let terrain = try makeBuilder().terrainBuilder
        let generator = try #require(terrain.terrainLOD
            .loadOrderTerrainLOD(lodWorldspace: "Tamriel"))
        let block = DistantLODBlock(
            kind: .terrain, level: 4, origin: CellCoordinate(x: 4, y: -4),
            path: "meshes\\terrain\\tamriel\\tamriel.4.4.-4.btr", clipMask: nil
        )
        #expect(generator.source(for: block) == nil)
        #expect(generator.terrainBlock(block) == nil)
        #expect(terrain.terrainLOD.loadOrderTerrainLOD(lodWorldspace: "Nowhere") == nil)
    }

    @Test(.enabled(if: Self.hasDevice)) func aFlowMapIsFoundUnderItsPluginFolder() throws {
        #expect(try makeBuilder().waterBuilder.flowMapPath(x: 6, y: -2) == nil)
        try writeLooseFile("textures/water/skyrim.esm/flow.6.-2.dds", Data([0]))
        let water = try makeBuilder().waterBuilder
        #expect(water.flowMapPath(x: 6, y: -2) == "textures\\water\\skyrim.esm\\flow.6.-2.dds")
    }
}
