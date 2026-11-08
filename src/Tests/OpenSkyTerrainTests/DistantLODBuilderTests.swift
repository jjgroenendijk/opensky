// A ring over a load order whose LOD files are missing: the settings file decides the
// blocks, and each block whose mesh is missing counts as missing instead of failing.

import Foundation
import Metal
import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyTagsTesting
@testable import OpenSkyTerrain
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct DistantLODBuilderTests {
    nonisolated private static let device = MTLCreateSystemDefaultDevice()

    nonisolated private static var hasDevice: Bool {
        device != nil
    }

    private static func settings() -> Data {
        var data = Data()
        data.appendUInt16(UInt16(bitPattern: Int16(-96)))
        data.appendUInt16(UInt16(bitPattern: Int16(-96)))
        data.appendUInt32(256)
        data.appendUInt32(4)
        data.appendUInt32(32)
        return data
    }

    private static func builder(files: [String: Data]) throws -> DistantLODBuilder {
        let device = try #require(Self.device)
        let source = InMemoryFileSource(files: files)
        let textures = try TextureLibrary(fileSystem: source, device: device)
        return DistantLODBuilder(
            fileSystem: source,
            meshes: MeshLibrary(fileSystem: source, device: device, textures: textures),
            textures: textures,
            configurationStore: .fallback()
        )
    }

    @Test(.enabled(if: hasDevice)) func withoutSettingsTheWorldspaceHasNoLOD() throws {
        let builder = try Self.builder(files: [:])
        #expect(builder.area(worldspace: "Tamriel") == nil)
        #expect(throws: (any Error).self) {
            try builder.build(worldspace: "Tamriel", center: .init(x: 0, y: 0), hiddenCells: [])
        }
    }

    @Test(.enabled(if: hasDevice)) func everyMissingBlockCountsAsMissing() throws {
        let builder = try Self.builder(files: ["lodsettings\\tamriel.lod": Self.settings()])
        let area = try #require(builder.area(worldspace: "Tamriel"))
        #expect(area.width == 256)
        let scene = try builder.build(
            worldspace: "Tamriel", center: .init(x: 0, y: 0), hiddenCells: []
        )
        #expect(scene.blockCount == 0)
        #expect(scene.missingBlockCount > 0)
        #expect(scene.treeInstanceCount == 0)
    }

    @Test func generatedKeysSitBesideTheVanillaFile() {
        let block = DistantLODBlock(
            kind: .terrain, level: 4, origin: CellCoordinate(x: 0, y: 4),
            path: "meshes\\terrain\\tamriel\\tamriel.4.0.4.btr", clipMask: nil
        )
        #expect(block.generatedMeshKey == "meshes\\terrain\\tamriel\\generated\\tamriel.4.0.4.btr")
        #expect(
            block.generatedDiffuseKey == "textures\\terrain\\tamriel\\generated\\tamriel.4.0.4.dds"
        )
        #expect(
            block.generatedNormalKey == "textures\\terrain\\tamriel\\generated\\tamriel.4.0.4_n.dds"
        )
        let bare = DistantLODBlock(
            kind: .objects, level: 4, origin: .init(x: 0, y: 0), path: "a.bto", clipMask: nil
        )
        #expect(bare.generatedMeshKey == "generated\\a.bto")
    }
}
