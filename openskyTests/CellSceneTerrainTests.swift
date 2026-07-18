// CellSceneBuilder terrain integration over synthetic fixtures only: a plugin
// whose target cell carries a compressed LAND record + an LTEX/TXST chain in a
// temp-dir VFS. Never extracted game files (AGENTS.md Legal & IP boundary).
// Needs a Metal device (RenderModel upload), gated like CellSceneBuilderTests.

import Foundation
import Metal
@testable import opensky
import simd
import Testing

struct CellSceneTerrainTests {
    private static let device = MTLCreateSystemDefaultDevice()
    private static var hasDevice: Bool {
        device != nil
    }

    private let dataURL: URL

    init() throws {
        dataURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-terrain-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
    }

    @Test(.enabled(if: Self.hasDevice)) func buildsTerrainFromLANDWithResolvedDiffuse() throws {
        // Only the resolved diffuse path carries bytes -> loads clean; a wrong
        // resolution would miss the file and bump missingTextureCount.
        try writeLooseFile("textures/landscape/dirt02.dds", Data([0, 1, 2, 3]))
        let scene = try build(pluginData: pluginWithLand(
            land: landFields(baseQuadrants: [0, 1, 2, 3], ltexFormID: 0x300),
            ltex: ltexRecord(formID: 0x300, textureSet: 0x400),
            txst: txstRecord(formID: 0x400, diffuse: "Landscape\\Dirt02.dds")
        ))
        // Four painted quadrants -> four terrain sub-meshes, all opaque.
        #expect(scene.summary.terrainQuadrantCount == 4)
        #expect(scene.renderScene.opaque.count == 4)
        #expect(scene.renderScene.alphaTested.isEmpty)
        // Diffuse resolved via BTXT -> LTEX -> TXST and found in the VFS.
        #expect(scene.summary.textureCount == 1)
        #expect(scene.summary.missingTextureCount == 0)
        // Cell (6,-2) south-west corner sits at world (6*4096, -2*4096, 0);
        // the first quadrant's origin vertex lands there.
        let origin = scene.renderScene.opaque[0].modelMatrix * SIMD4<Float>(0, 0, 0, 1)
        #expect(SIMD3(origin.x, origin.y, origin.z) == SIMD3<Float>(24576, -8192, 0))
    }

    @Test(.enabled(if: Self.hasDevice)) func hidesQuadrantsPerXCLCFlags() throws {
        // XCLC quad-flags 0x2 | 0x8 hide quadrants 1 and 3 -> two remain.
        let scene = try build(pluginData: pluginWithLand(
            land: landFields(baseQuadrants: [0, 1, 2, 3], ltexFormID: 0), quadFlags: 0x2 | 0x8
        ))
        #expect(scene.summary.terrainQuadrantCount == 2)
        #expect(scene.renderScene.opaque.count == 2)
    }

    @Test(.enabled(if: Self.hasDevice)) func fallbackPlaneAtDNAMWhenNoLAND() throws {
        // No LAND, WRLD carries DNAM default land height -27000 -> one plane.
        let scene = try build(pluginData: pluginWithLand(land: Data(), defaultLandHeight: -27000))
        #expect(scene.summary.terrainQuadrantCount == 1)
        let bounds = try #require(scene.bounds)
        #expect(bounds.min.z == -27000)
        #expect(bounds.max.z == -27000)
    }

    @Test(.enabled(if: Self.hasDevice)) func noTerrainWhenNoLANDAndNoDNAM() throws {
        // A cell with no LAND and a DNAM-less WRLD draws no ground.
        let scene = try build(pluginData: pluginWithLand(land: Data()))
        #expect(scene.summary.terrainQuadrantCount == 0)
        #expect(scene.renderScene.drawCount == 0)
    }
}

/// Fixture builders + harness in an extension to keep the test body small.
extension CellSceneTerrainTests {
    private func writeLooseFile(_ relativePath: String, _ contents: Data) throws {
        let url = dataURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: url)
    }

    /// LAND field payload: flat VHGT (heights all 0) + one BTXT per quadrant
    /// pointing at `ltexFormID`. `pluginWithLand` wraps it in a compressed
    /// record, matching real LAND on disk (zlib, flag bit 18).
    private func landFields(baseQuadrants: [UInt8], ltexFormID: UInt32) -> Data {
        var vhgt = Data()
        vhgt.appendFloat32(0) // anchor
        vhgt.append(contentsOf: [UInt8](repeating: 0, count: 33 * 33))
        vhgt.append(contentsOf: [0, 0, 0])
        var fields = ESMFixture.field("VHGT", vhgt)
        for quadrant in baseQuadrants {
            var btxt = Data()
            btxt.appendUInt32(ltexFormID)
            btxt.append(quadrant)
            btxt.append(0)
            btxt.appendUInt16(0)
            fields += ESMFixture.field("BTXT", btxt)
        }
        return fields
    }

    private func ltexRecord(formID: UInt32, textureSet: UInt32) -> Data {
        var tnam = Data()
        tnam.appendUInt32(textureSet)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("LTEX\(formID)"))
            + ESMFixture.field("TNAM", tnam)
        return ESMFixture.record("LTEX", formID: formID, data: fields)
    }

    private func txstRecord(formID: UInt32, diffuse: String) -> Data {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("TXST\(formID)"))
            + ESMFixture.field("TX00", ESMFixture.zstring(diffuse))
        return ESMFixture.record("TXST", formID: formID, data: fields)
    }

    /// Plugin whose target cell carries a LAND record (compressed) in its
    /// temporary-children group, plus optional LTEX/TXST top groups the base
    /// texture resolves through and a WRLD DNAM default land height. Empty
    /// `land` -> no LAND record (fallback-plane path).
    private func pluginWithLand(
        land: Data,
        ltex: Data = Data(),
        txst: Data = Data(),
        quadFlags: UInt32 = 0,
        defaultLandHeight: Float? = nil,
        grid: (x: Int32, y: Int32) = (6, -2)
    ) -> Data {
        let cellFormID: UInt32 = 0x2B
        let worldFormID: UInt32 = 0x1A
        var cellFields = ESMFixture.field("EDID", ESMFixture.zstring("TestCell06"))
        var xclc = Data()
        xclc.appendUInt32(UInt32(bitPattern: grid.x))
        xclc.appendUInt32(UInt32(bitPattern: grid.y))
        xclc.appendUInt32(quadFlags)
        cellFields += ESMFixture.field("XCLC", xclc)
        let cell = ESMFixture.record("CELL", formID: cellFormID, data: cellFields)
        let landRecordBytes = land.isEmpty
            ? Data()
            : ESMFixture.compressedRecord("LAND", formID: 0x2C, fieldData: land)
        let children = ESMFixture.childGroup(
            parent: cellFormID, groupType: 9, contents: landRecordBytes
        )
        let cellChildren = ESMFixture.childGroup(
            parent: cellFormID, groupType: 6, contents: children
        )
        let subBlock = ESMFixture.exteriorBlock(
            x: Int16(grid.x >> 3), y: Int16(grid.y >> 3),
            groupType: 5, contents: cell + cellChildren
        )
        let block = ESMFixture.exteriorBlock(
            x: Int16(grid.x >> 5), y: Int16(grid.y >> 5), groupType: 4, contents: subBlock
        )
        let worldChildren = ESMFixture.childGroup(
            parent: worldFormID, groupType: 1, contents: block
        )
        var worldFields = ESMFixture.field("EDID", ESMFixture.zstring("Tamriel"))
        if let defaultLandHeight {
            var dnam = Data()
            dnam.appendFloat32(defaultLandHeight)
            dnam.appendFloat32(-14000) // default water height, unused here
            worldFields += ESMFixture.field("DNAM", dnam)
        }
        let wrld = ESMFixture.record("WRLD", formID: worldFormID, data: worldFields)
        return ESMFixture.tes4()
            + ESMFixture.topGroup("WRLD", contents: wrld + worldChildren)
            + ESMFixture.topGroup("LTEX", contents: ltex)
            + ESMFixture.topGroup("TXST", contents: txst)
            + ESMFixture.topGroup("STAT", contents: Data())
    }

    private func build(pluginData: Data) throws -> CellScene {
        let device = try #require(Self.device)
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let builder = try CellSceneBuilder(
            file: ESMFile(data: pluginData),
            meshes: meshes,
            textures: textures
        )
        return try builder.buildScene(worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2)
    }
}
