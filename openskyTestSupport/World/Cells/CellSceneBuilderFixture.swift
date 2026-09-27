// The `CellSceneBuilderTests` fixture: a temp-dir VFS, the synthetic plugin and
// NIF builders every cell-scene suite composes, and the two Metal gates. Both
// test targets compile this folder, because the M11 real-data acceptance suite
// builds the same synthetic cell to compare a real render against.
//
// Fixtures are synthetic throughout — ESMFixture plugin bytes and NIFFixture
// meshes in a temp directory, never extracted game files (AGENTS.md Legal & IP
// boundary). The suite's own tests are extensions of this type under
// openskyTests/. See openskyTestSupport/AGENTS.md.

import Foundation
import Metal
@testable import opensky
import simd
import Testing

struct TeleportFixture {
    let door: UInt32
    let position: SIMD3<Float>
    let rotation: SIMD3<Float>
}

struct CellSceneBuilderTests {
    static let device = MTLCreateSystemDefaultDevice()
    static var hasDevice: Bool {
        device != nil
    }

    static let staticAttributes: UInt16 = 0x1B
    static let staticStrideDwords = 7

    fileprivate let dataURL: URL

    init() throws {
        dataURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-cellscene-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
    }
}

/// Fixture builders live in an extension to keep the test type body small;
/// they hold no assertions of their own.
extension CellSceneBuilderTests {
    // MARK: - NIF fixtures

    func writeLooseFile(_ relativePath: String, _ contents: Data) throws {
        let url = dataURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url)
    }

    /// One static-layout vertex record at the given position (see
    /// MeshLibraryTests for the interleaved layout the attributes select).
    func vertexRecord(position: SIMD3<Float>) -> Data {
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
    func staticNIF(positions: [SIMD3<Float>]) -> Data {
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

    func unitNIF() -> Data {
        staticNIF(positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 1)])
    }

    // MARK: - Plugin fixtures

    func statRecord(formID: UInt32, modelPath: String?) -> Data {
        var fields = Data()
        if let modelPath {
            fields += ESMFixture.field("MODL", ESMFixture.zstring(modelPath))
        }
        return ESMFixture.record("STAT", formID: formID, data: fields)
    }

    /// One MSTT/TREE/FURN/ACTI/CONT record, same EDID/MODL shape as STAT.
    func modelBaseRecord(
        type: String,
        formID: UInt32,
        modelPath: String?,
        displayName: String? = nil,
        activateTextOverride: String? = nil
    ) -> Data {
        var fields = Data()
        if let displayName {
            fields += ESMFixture.field("FULL", ESMFixture.zstring(displayName))
        }
        if let modelPath {
            fields += ESMFixture.field("MODL", ESMFixture.zstring(modelPath))
        }
        if let activateTextOverride {
            fields += ESMFixture.field(
                "RNAM", ESMFixture.zstring(activateTextOverride)
            )
        }
        return ESMFixture.record(type, formID: formID, data: fields)
    }

    func refrRecord(
        formID: UInt32,
        base: UInt32,
        position: SIMD3<Float> = .zero,
        rotation: SIMD3<Float> = .zero,
        scale: Float? = nil,
        includePlacement: Bool = true,
        teleport: TeleportFixture? = nil
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
        if let teleport {
            var xtel = Data()
            xtel.appendUInt32(teleport.door)
            for value in [
                teleport.position.x, teleport.position.y, teleport.position.z,
                teleport.rotation.x, teleport.rotation.y, teleport.rotation.z
            ] {
                xtel.appendFloat32(value)
            }
            xtel.appendUInt32(0)
            fields += ESMFixture.field("XTEL", xtel)
        }
        return ESMFixture.record("REFR", formID: formID, data: fields)
    }

    func interiorCellGroup(
        formID: UInt32,
        refs: Data,
        blockLabel: UInt32? = nil,
        subBlockLabel: UInt32? = nil
    ) -> Data {
        var flags = Data()
        flags.appendUInt16(Cell.Flags.interior.rawValue)
        let cell = ESMFixture.record(
            "CELL",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestInterior"))
                + ESMFixture.field("DATA", flags)
        )
        let temporary = ESMFixture.childGroup(parent: formID, groupType: 9, contents: refs)
        let children = ESMFixture.childGroup(
            parent: formID, groupType: 6, contents: temporary
        )
        let objectID = FormID(formID).objectID
        var subLabel = Data()
        subLabel.appendUInt32(subBlockLabel ?? ((objectID / 10) % 10))
        let sub = ESMFixture.group(
            label: subLabel, groupType: 3, contents: cell + children
        )
        var block = Data()
        block.appendUInt32(blockLabel ?? (objectID % 10))
        return ESMFixture.group(label: block, groupType: 2, contents: sub)
    }

    /// TES4 + WRLD tree (world children -> block -> sub-block -> CELL +
    /// children with persistent + temporary groups) + STAT top group + one
    /// top group per non-empty entry in `modelBaseRecords` (keyed by record
    /// type, e.g. "TREE") — mirrors the real plugin's one-group-per-type
    /// layout instead of mixing types under a single label.
    func plugin(
        worldspaceEditorID: String = "Tamriel",
        cellEditorID: String = "TestCell06",
        grid: (x: Int32, y: Int32) = (6, -2),
        persistentRefs: Data = Data(),
        temporaryRefs: Data = Data(),
        statRecords: Data = Data(),
        modelBaseRecords: [String: Data] = [:],
        cellFlags: UInt16 = 0,
        cellWaterHeightBits: UInt32? = nil,
        cellWaterType: UInt32? = nil,
        worldDefaultWaterHeight: Float? = nil,
        worldWaterType: UInt32? = nil,
        worldFlags: UInt8 = 0,
        parentWorld: UInt32? = nil,
        parentFlags: UInt16 = 0,
        extraWorldRecords: Data = Data(),
        extraWorldChildren: Data = Data(),
        waterRecords: Data = Data(),
        interiorRecords: Data = Data()
    ) -> Data {
        let cellFormID: UInt32 = 0x2B
        let worldFormID: UInt32 = 0x1A
        let cell = ESMFixture.record(
            "CELL",
            formID: cellFormID,
            data: cellFields(
                editorID: cellEditorID,
                grid: grid,
                flags: cellFlags,
                waterHeightBits: cellWaterHeightBits,
                waterType: cellWaterType
            )
        )
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
            parent: worldFormID, groupType: 1, contents: extraWorldChildren + block
        )
        let wrld = worldRecord(
            formID: worldFormID,
            editorID: worldspaceEditorID,
            defaultWaterHeight: worldDefaultWaterHeight,
            waterType: worldWaterType,
            flags: worldFlags,
            parent: parentWorld,
            parentFlags: parentFlags
        )
        let modelBaseGroups = modelBaseRecords
            .sorted { $0.key < $1.key } // deterministic fixture bytes
            .map { type, records in ESMFixture.topGroup(type, contents: records) }
            .reduce(Data(), +)
        return ESMFixture.tes4()
            + ESMFixture.topGroup(
                "WRLD", contents: extraWorldRecords + wrld + worldChildren
            )
            + ESMFixture.topGroup("STAT", contents: statRecords)
            + modelBaseGroups
            + ESMFixture.topGroup("WATR", contents: waterRecords)
            + (interiorRecords.isEmpty
                ? Data()
                : ESMFixture.topGroup("CELL", contents: interiorRecords))
    }

    func makeBuilder(pluginData: Data, device: MTLDevice) throws -> CellSceneBuilder {
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        return try CellSceneBuilder(
            file: ESMFile(data: pluginData),
            meshes: meshes,
            textures: textures,
            fileSystem: vfs
        )
    }

    func build(
        pluginData: Data,
        gridX: Int32 = 6,
        gridY: Int32 = -2,
        state: WorldStateSnapshot = .empty
    ) throws -> CellScene {
        let device = try #require(Self.device)
        let builder = try makeBuilder(pluginData: pluginData, device: device)
        return try builder.buildScene(
            worldspaceEditorID: "Tamriel", gridX: gridX, gridY: gridY, state: state
        )
    }
}

/// Worldspace and interior-cell record builders. The M11 real-data acceptance
/// suite composes the same synthetic worldspace, so these live beside the rest of
/// the fixture rather than with the water suite that first needed them.
extension CellSceneBuilderTests {
    func worldRecord(
        formID: UInt32,
        editorID: String,
        defaultWaterHeight: Float? = nil,
        waterType: UInt32? = nil,
        flags: UInt8 = 0,
        parent: UInt32? = nil,
        parentFlags: UInt16 = 0
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if let parent {
            var wnam = Data()
            wnam.appendUInt32(parent)
            var pnam = Data()
            pnam.appendUInt16(parentFlags)
            fields += ESMFixture.field("WNAM", wnam)
                + ESMFixture.field("PNAM", pnam)
        }
        if let defaultWaterHeight {
            var dnam = Data()
            dnam.appendFloat32(-27000)
            dnam.appendFloat32(defaultWaterHeight)
            fields += ESMFixture.field("DNAM", dnam)
        }
        if let waterType {
            var nam2 = Data()
            nam2.appendUInt32(waterType)
            fields += ESMFixture.field("NAM2", nam2)
        }
        fields += ESMFixture.field("DATA", Data([flags]))
        return ESMFixture.record("WRLD", formID: formID, data: fields)
    }

    func cellFields(
        editorID: String,
        grid: (x: Int32, y: Int32),
        flags: UInt16,
        waterHeightBits: UInt32?,
        waterType: UInt32?
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        var xclc = Data()
        xclc.appendUInt32(UInt32(bitPattern: grid.x))
        xclc.appendUInt32(UInt32(bitPattern: grid.y))
        xclc.appendUInt32(0)
        fields += ESMFixture.field("XCLC", xclc)
        if flags != 0 {
            var data = Data()
            data.appendUInt16(flags)
            fields += ESMFixture.field("DATA", data)
        }
        if let waterHeightBits {
            var xclw = Data()
            xclw.appendUInt32(waterHeightBits)
            fields += ESMFixture.field("XCLW", xclw)
        }
        if let waterType {
            var xcwt = Data()
            xcwt.appendUInt32(waterType)
            fields += ESMFixture.field("XCWT", xcwt)
        }
        return fields
    }

    func collisionRenderNIF() -> Data {
        NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 2),
                children: [1]
            )),
            .init("BSTriShape", NIFFixture.bsTriShape(
                attributes: Self.staticAttributes,
                strideDwords: Self.staticStrideDwords,
                vertexRecords: [
                    SIMD3<Float>(0, 0, 0),
                    SIMD3<Float>(1, 0, 0),
                    SIMD3<Float>(0, 1, 1)
                ].map(vertexRecord(position:)),
                triangles: [0, 1, 2]
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 3)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 4)),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1))
        ])
    }
}
