// CellSceneBuilder tests over synthetic fixtures only: ESMFixture plugin
// bytes (WRLD tree + STAT/MSTT/TREE/FURN/ACTI/CONT top groups) + NIFFixture
// meshes in a temp-dir VFS. Never extracted game files (AGENTS.md Legal & IP
// boundary). Needs a Metal device (RenderModel upload), gated like
// MeshLibraryTests.

import Foundation
import Metal
@testable import opensky
import simd
import Testing

struct CellSceneBuilderTests {
    fileprivate static let device = MTLCreateSystemDefaultDevice()
    fileprivate static var hasDevice: Bool {
        device != nil
    }

    fileprivate static let staticAttributes: UInt16 = 0x1B
    fileprivate static let staticStrideDwords = 7

    fileprivate let dataURL: URL

    init() throws {
        dataURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-cellscene-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
    }

    // MARK: - Happy path

    @Test(.enabled(if: Self.hasDevice)) func drawsAllResolvableRefs() throws {
        try writeLooseFile("meshes/arch/wall.nif", staticNIF(positions: [
            SIMD3(0, 0, 0), SIMD3(2, 0, 0), SIMD3(0, 4, 6)
        ]))
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100, position: SIMD3(10, 20, 30))
                + refrRecord(formID: 0x201, base: 0x100, position: SIMD3(-10, -20, -30)),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
        ))
        #expect(scene.summary.totalRefCount == 2)
        #expect(scene.summary.drawnRefCount == 2)
        #expect(scene.summary.skippedRefCount == 0)
        #expect(scene.summary.modelCount == 1)
        // One shared model -> one instanced group carrying both refs.
        #expect(scene.renderScene.drawCount == 1)
        #expect(scene.renderScene.instanceCount == 2)
        // Model extents (0..2, 0..4, 0..6) translated by each REFR position.
        let bounds = try #require(scene.bounds)
        #expect(bounds.min == SIMD3(-10, -20, -30))
        #expect(bounds.max == SIMD3(12, 24, 36))
    }

    @Test(.enabled(if: Self.hasDevice)) func scaledRefScalesBounds() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100, scale: 2),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
        ))
        let bounds = try #require(scene.bounds)
        #expect(bounds.min == SIMD3(0, 0, 0))
        #expect(bounds.max == SIMD3(2, 2, 2))
    }

    @Test(.enabled(if: Self.hasDevice)) func traversesPersistentAndTemporaryChildren() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let scene = try build(pluginData: plugin(
            persistentRefs: refrRecord(formID: 0x200, base: 0x100),
            temporaryRefs: refrRecord(formID: 0x201, base: 0x100),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
        ))
        #expect(scene.summary.totalRefCount == 2)
        #expect(scene.summary.drawnRefCount == 2)
    }

    // MARK: - Skip taxonomy

    @Test(.enabled(if: Self.hasDevice)) func skipsRefWithUnsupportedBase() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100)
                + refrRecord(formID: 0x201, base: 0x999), // no STAT/ModelBase with this ID
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
        ))
        #expect(scene.summary.totalRefCount == 2)
        #expect(scene.summary.drawnRefCount == 1)
        #expect(scene.summary.unsupportedBaseSkipCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func drawsAllFiveModelBaseTypes() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let types = ["MSTT", "TREE", "FURN", "ACTI", "CONT"]
        var records: [String: Data] = [:]
        var refs = Data()
        for (index, type) in types.enumerated() {
            let formID = UInt32(0x300 + index)
            records[type] = modelBaseRecord(type: type, formID: formID, modelPath: "arch\\wall.nif")
            refs += refrRecord(formID: UInt32(0x400 + index), base: formID)
        }
        let scene = try build(pluginData: plugin(temporaryRefs: refs, modelBaseRecords: records))
        #expect(scene.summary.totalRefCount == types.count)
        #expect(scene.summary.drawnRefCount == types.count)
        #expect(scene.summary.skippedRefCount == 0)
        // All five bases share one NIF -> one group, five instances.
        #expect(scene.renderScene.drawCount == 1)
        #expect(scene.renderScene.instanceCount == types.count)
    }

    @Test(.enabled(if: Self.hasDevice)) func skipsMarkerModelBaseWithoutModel() throws {
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100),
            modelBaseRecords: ["TREE": modelBaseRecord(type: "TREE", formID: 0x100, modelPath: nil)]
        ))
        #expect(scene.summary.markerSkipCount == 1)
        #expect(scene.summary.drawnRefCount == 0)
    }

    @Test(.enabled(if: Self.hasDevice)) func skipsMarkerSTATWithoutModel() throws {
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100),
            statRecords: statRecord(formID: 0x100, modelPath: nil)
        ))
        #expect(scene.summary.markerSkipCount == 1)
        #expect(scene.summary.drawnRefCount == 0)
        #expect(scene.renderScene.drawCount == 0)
        #expect(scene.bounds == nil)
    }

    @Test(.enabled(if: Self.hasDevice)) func skipsMissingNIFAndContinues() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100)
                + refrRecord(formID: 0x201, base: 0x101),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\absent.nif")
                + statRecord(formID: 0x101, modelPath: "arch\\wall.nif")
        ))
        #expect(scene.summary.modelFailureSkipCount == 1)
        #expect(scene.summary.drawnRefCount == 1)
        #expect(scene.renderScene.drawCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func skipsMalformedNIFAndContinues() throws {
        try writeLooseFile("meshes/arch/bad.nif", Data("not a nif file".utf8))
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100)
                + refrRecord(formID: 0x201, base: 0x101),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\bad.nif")
                + statRecord(formID: 0x101, modelPath: "arch\\wall.nif")
        ))
        #expect(scene.summary.modelFailureSkipCount == 1)
        #expect(scene.summary.drawnRefCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func countsMalformedREFR() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100)
                + refrRecord(formID: 0x201, base: 0x100, includePlacement: false),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
        ))
        #expect(scene.summary.totalRefCount == 2)
        #expect(scene.summary.malformedRefSkipCount == 1)
        #expect(scene.summary.drawnRefCount == 1)
    }

    // MARK: - Structural failures

    @Test(.enabled(if: Self.hasDevice)) func missingWorldspaceThrows() throws {
        let device = try #require(Self.device)
        let builder = try makeBuilder(pluginData: plugin(), device: device)
        #expect(throws: CellSceneError.worldspaceNotFound(editorID: "Nirn")) {
            _ = try builder.buildScene(worldspaceEditorID: "Nirn", gridX: 6, gridY: -2)
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func gridMismatchThrowsCellNotFound() throws {
        let expected = CellSceneError.cellNotFound(
            worldspaceEditorID: "Tamriel", gridX: 7, gridY: 7
        )
        #expect(throws: expected) {
            _ = try build(pluginData: plugin(), gridX: 7, gridY: 7)
        }
    }

    // MARK: - Grouping + summary

    @Test(.enabled(if: Self.hasDevice)) func groupsInstancesByModel() throws {
        try writeLooseFile("meshes/arch/aaa.nif", unitNIF())
        try writeLooseFile("meshes/arch/zzz.nif", unitNIF())
        // Interleave refs of two models; grouped output must make instances
        // of one model adjacent, ordered by path (aaa first) then FormID.
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100, position: SIMD3(1, 0, 0))
                + refrRecord(formID: 0x201, base: 0x101, position: SIMD3(2, 0, 0))
                + refrRecord(formID: 0x202, base: 0x100, position: SIMD3(3, 0, 0))
                + refrRecord(formID: 0x203, base: 0x101, position: SIMD3(4, 0, 0)),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\zzz.nif")
                + statRecord(formID: 0x101, modelPath: "arch\\aaa.nif")
        ))
        let opaque = scene.renderScene.opaque
        try #require(opaque.count == 2)
        // aaa group (refs 0x201, 0x203) first, then zzz (0x200, 0x202);
        // instances within a group ordered by FormID.
        let translations = opaque.map { group in
            group.instances.map { instance in
                let column = instance.modelMatrix.columns.3
                return SIMD3(column.x, column.y, column.z)
            }
        }
        #expect(translations == [
            [SIMD3(2, 0, 0), SIMD3(4, 0, 0)],
            [SIMD3(1, 0, 0), SIMD3(3, 0, 0)]
        ])
        // Groups draw distinct GPU meshes; each group is one instanced call.
        #expect(opaque[0].mesh !== opaque[1].mesh)
    }

    @Test(.enabled(if: Self.hasDevice)) func summaryLineReportsCounts() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100)
                + refrRecord(formID: 0x201, base: 0x999),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
        ))
        // Fixture NIF has no shader property -> untextured placeholder, so
        // texture counters stay zero.
        #expect(scene.summary.summaryLine == "[INFO] TestCell06 (6,-2): 2 refs, 1 drawn, "
            + "1 skipped (1 unsupported-base), 1 models, 0 textures (0 missing)")
    }
}

/// Fixture builders live in an extension to keep the test type body small;
/// they hold no assertions of their own.
extension CellSceneBuilderTests {
    // MARK: - NIF fixtures

    private func writeLooseFile(_ relativePath: String, _ contents: Data) throws {
        let url = dataURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url)
    }

    /// One static-layout vertex record at the given position (see
    /// MeshLibraryTests for the interleaved layout the attributes select).
    private func vertexRecord(position: SIMD3<Float>) -> Data {
        var record = Data()
        record.appendFloat32(position.x)
        record.appendFloat32(position.y)
        record.appendFloat32(position.z)
        record.appendFloat32(0) // bitangent X
        record.appendFloat16(0)
        record.appendFloat16(0)
        record.append(contentsOf: [128, 128, 255, 128]) // normal + bitangent Y
        record.append(contentsOf: [255, 128, 128, 128]) // tangent + bitangent Z
        return record
    }

    /// Static one-triangle NIF spanning the given three positions — known
    /// extents for bounds assertions.
    private func staticNIF(positions: [SIMD3<Float>]) -> Data {
        NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("BSTriShape", NIFFixture.bsTriShape(
                attributes: Self.staticAttributes,
                strideDwords: Self.staticStrideDwords,
                vertexRecords: positions.map(vertexRecord(position:)),
                triangles: [0, 1, 2]
            ))
        ])
    }

    private func unitNIF() -> Data {
        staticNIF(positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 1)])
    }

    // MARK: - Plugin fixtures

    private func statRecord(formID: UInt32, modelPath: String?) -> Data {
        var fields = Data()
        if let modelPath {
            fields += ESMFixture.field("MODL", ESMFixture.zstring(modelPath))
        }
        return ESMFixture.record("STAT", formID: formID, data: fields)
    }

    /// One MSTT/TREE/FURN/ACTI/CONT record, same EDID/MODL shape as STAT.
    private func modelBaseRecord(type: String, formID: UInt32, modelPath: String?) -> Data {
        var fields = Data()
        if let modelPath {
            fields += ESMFixture.field("MODL", ESMFixture.zstring(modelPath))
        }
        return ESMFixture.record(type, formID: formID, data: fields)
    }

    private func refrRecord(
        formID: UInt32,
        base: UInt32,
        position: SIMD3<Float> = .zero,
        rotation: SIMD3<Float> = .zero,
        scale: Float? = nil,
        includePlacement: Bool = true
    ) -> Data {
        var name = Data()
        name.appendUInt32(base)
        var fields = ESMFixture.field("NAME", name)
        if includePlacement {
            var data = Data()
            for value in [
                position.x, position.y, position.z,
                rotation.x, rotation.y, rotation.z
            ] {
                data.appendFloat32(value)
            }
            fields += ESMFixture.field("DATA", data)
        }
        if let scale {
            var xscl = Data()
            xscl.appendFloat32(scale)
            fields += ESMFixture.field("XSCL", xscl)
        }
        return ESMFixture.record("REFR", formID: formID, data: fields)
    }

    /// TES4 + WRLD tree (world children -> block -> sub-block -> CELL +
    /// children with persistent + temporary groups) + STAT top group + one
    /// top group per non-empty entry in `modelBaseRecords` (keyed by record
    /// type, e.g. "TREE") — mirrors the real plugin's one-group-per-type
    /// layout instead of mixing types under a single label.
    private func plugin(
        worldspaceEditorID: String = "Tamriel",
        cellEditorID: String = "TestCell06",
        grid: (x: Int32, y: Int32) = (6, -2),
        persistentRefs: Data = Data(),
        temporaryRefs: Data = Data(),
        statRecords: Data = Data(),
        modelBaseRecords: [String: Data] = [:]
    ) -> Data {
        let cellFormID: UInt32 = 0x2B
        let worldFormID: UInt32 = 0x1A
        var cellFields = ESMFixture.field("EDID", ESMFixture.zstring(cellEditorID))
        var xclc = Data()
        xclc.appendUInt32(UInt32(bitPattern: grid.x))
        xclc.appendUInt32(UInt32(bitPattern: grid.y))
        xclc.appendUInt32(0)
        cellFields += ESMFixture.field("XCLC", xclc)
        let cell = ESMFixture.record("CELL", formID: cellFormID, data: cellFields)
        let children = ESMFixture.childGroup(
            parent: cellFormID, groupType: 8, contents: persistentRefs
        ) + ESMFixture.childGroup(
            parent: cellFormID, groupType: 9, contents: temporaryRefs
        )
        let cellChildren = ESMFixture.childGroup(
            parent: cellFormID, groupType: 6, contents: children
        )
        // Block labels are hints the builder must ignore (unreliable per
        // UESP); grid >> 3 / >> 5 matches the vanilla nesting math anyway.
        let subBlock = ESMFixture.exteriorBlock(
            x: Int16(grid.x >> 3), y: Int16(grid.y >> 3),
            groupType: 5, contents: cell + cellChildren
        )
        let block = ESMFixture.exteriorBlock(
            x: Int16(grid.x >> 5), y: Int16(grid.y >> 5),
            groupType: 4, contents: subBlock
        )
        let worldChildren = ESMFixture.childGroup(
            parent: worldFormID, groupType: 1, contents: block
        )
        let wrld = ESMFixture.record(
            "WRLD", formID: worldFormID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(worldspaceEditorID))
        )
        let modelBaseGroups = modelBaseRecords
            .sorted { $0.key < $1.key } // deterministic fixture bytes
            .map { type, records in ESMFixture.topGroup(type, contents: records) }
            .reduce(Data(), +)
        return ESMFixture.tes4()
            + ESMFixture.topGroup("WRLD", contents: wrld + worldChildren)
            + ESMFixture.topGroup("STAT", contents: statRecords)
            + modelBaseGroups
    }

    private func makeBuilder(pluginData: Data, device: MTLDevice) throws -> CellSceneBuilder {
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        return try CellSceneBuilder(
            file: ESMFile(data: pluginData),
            meshes: meshes,
            textures: textures
        )
    }

    private func build(
        pluginData: Data,
        gridX: Int32 = 6,
        gridY: Int32 = -2
    ) throws -> CellScene {
        let device = try #require(Self.device)
        let builder = try makeBuilder(pluginData: pluginData, device: device)
        return try builder.buildScene(
            worldspaceEditorID: "Tamriel", gridX: gridX, gridY: gridY
        )
    }
}
