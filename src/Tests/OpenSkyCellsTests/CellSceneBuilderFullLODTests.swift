// The distant ring draws temporary Is Full LOD references from cells that are not loaded.
// Synthetic plugin only.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyTagsTesting
import OpenSkyWorldTesting
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct CellSceneBuilderFullLODTests: CellSceneBuilderFixture {
    let dataURL: URL

    init() throws {
        dataURL = try Self.makeDataDirectory()
    }

    /// The record header's flags sit after the type and the size.
    private func withFlags(_ record: Data, _ flags: UInt32) -> Data {
        var bytes = record
        let start = bytes.startIndex + 8
        for byte in 0 ..< 4 {
            bytes[start + byte] |= UInt8(truncatingIfNeeded: flags >> (8 * UInt32(byte)))
        }
        return bytes
    }

    private func fullLOD(_ record: Data) -> Data {
        withFlags(record, PlacedReference.fullLODFlag)
    }

    private func makeBuilder(temporaryRefs: Data) throws -> CellSceneBuilder {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let device = try #require(Self.device)
        return try makeBuilder(
            pluginData: plugin(
                temporaryRefs: temporaryRefs,
                statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
            ),
            device: device
        )
    }

    @Test(.enabled(if: Self.hasDevice)) func findsTheCellOfAFlaggedTemporaryReference() throws {
        let builder = try makeBuilder(
            temporaryRefs: fullLOD(refrRecord(formID: 0x200, base: 0x100))
                + refrRecord(formID: 0x201, base: 0x100)
        )
        let world = try builder.records.worldChildrenGroup(editorID: "Tamriel", localized: false)
        #expect(builder.referenceBuilder.largeReferences
            .temporaryFullLODCells(in: world) == [CellCoordinate(
                x: 6,
                y: -2
            )])

        let distant = builder.referenceBuilder.largeReferences.temporaryFullLODPlacements(
            worldspaceEditorID: "Tamriel", loadedCells: []
        )
        #expect(distant.placements.count == 1)
        #expect(distant.watchedObjectIDs.contains(0x200))
        #expect(!distant.watchedObjectIDs.contains(0x201))
    }

    @Test(.enabled(if: Self.hasDevice)) func aLoadedCellDrawsItsOwn() throws {
        let builder = try makeBuilder(temporaryRefs: fullLOD(refrRecord(
            formID: 0x200,
            base: 0x100
        )))
        let distant = builder.referenceBuilder.largeReferences.temporaryFullLODPlacements(
            worldspaceEditorID: "Tamriel", loadedCells: [CellCoordinate(x: 6, y: -2)]
        )
        #expect(distant.placements.isEmpty)
    }

    @Test(.enabled(if: Self.hasDevice)) func anUnflaggedCellIsNotIndexed() throws {
        let builder = try makeBuilder(temporaryRefs: refrRecord(formID: 0x201, base: 0x100))
        let world = try builder.records.worldChildrenGroup(editorID: "Tamriel", localized: false)
        #expect(builder.referenceBuilder.largeReferences.temporaryFullLODCells(in: world).isEmpty)
    }

    /// The worldspace persistent CELL sits directly in the world children, outside any block.
    private func persistentCell(holding refs: Data) -> Data {
        ESMFixture.record("CELL", formID: 0x60, data: cellFields(
            editorID: "Persistent", grid: (0, 0), flags: 0, waterHeightBits: nil, waterType: nil
        )) + ESMFixture.childGroup(
            parent: 0x60, groupType: 6,
            contents: ESMFixture.childGroup(parent: 0x60, groupType: 8, contents: refs)
        )
    }

    private func makeBuilder(persistentRefs: Data) throws -> CellSceneBuilder {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let device = try #require(Self.device)
        return try makeBuilder(
            pluginData: plugin(
                statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif"),
                extraWorldChildren: persistentCell(holding: persistentRefs)
            ),
            device: device
        )
    }

    @Test(.enabled(if: Self.hasDevice)) func drawsAFlaggedPersistentReferenceOutsideTheLoadedCells(
    ) throws {
        let builder = try makeBuilder(
            persistentRefs: fullLOD(refrRecord(formID: 0x300, base: 0x100))
                + refrRecord(formID: 0x301, base: 0x100)
        )
        let distant = builder.referenceBuilder.largeReferences.fullLODPlacements(
            worldspaceEditorID: "Tamriel", loadedCells: []
        )
        #expect(distant.placements.count == 1)
        #expect(distant.watchedObjectIDs == [0x300])
        let loaded = builder.referenceBuilder.largeReferences.fullLODPlacements(
            worldspaceEditorID: "Tamriel", loadedCells: [CellCoordinate(x: 0, y: 0)]
        )
        #expect(loaded.placements.isEmpty)
    }

    @Test(.enabled(if: Self.hasDevice)) func aWorldWithoutLargeReferencesDrawsNone() throws {
        let builder = try makeBuilder(persistentRefs: Data())
        let cells: Set = [CellCoordinate(x: 6, y: -2)]
        for _ in 0 ..< 2 {
            let large = builder.referenceBuilder.largeReferences.largeReferencePlacements(
                worldspaceEditorID: "Tamriel", cells: cells
            )
            #expect(large.placements.isEmpty)
        }
        #expect(builder.caches.largeReferenceIndex.count == 1)
        let unknown = builder.referenceBuilder.largeReferences.fullLODPlacements(
            worldspaceEditorID: "Nowhere", loadedCells: []
        )
        #expect(unknown.placements.isEmpty)
    }

    /// A reference whose enable parent starts disabled is not drawn, and the parent is
    /// watched, so enabling it builds the ring again.
    @Test(.enabled(if: Self.hasDevice)) func aRingReferenceFollowsItsEnableParent() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let disabledParent = withFlags(refrRecord(formID: 0x400, base: 0x100), 0x800)
        let builder = try makeBuilder(
            pluginData: plugin(
                temporaryRefs: fullLOD(refrRecord(formID: 0x200, base: 0x100, enableParent: 0x400)),
                statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif"),
                extraWorldChildren: persistentCell(holding: disabledParent
                    + fullLOD(refrRecord(formID: 0x300, base: 0x100, enableParent: 0x400)))
            ),
            device: #require(Self.device)
        )
        let temporary = builder.referenceBuilder.largeReferences.temporaryFullLODPlacements(
            worldspaceEditorID: "Tamriel", loadedCells: []
        )
        #expect(temporary.placements.isEmpty)
        #expect(temporary.watchedObjectIDs == [0x200, 0x400])
        let persistent = builder.referenceBuilder.largeReferences.fullLODPlacements(
            worldspaceEditorID: "Tamriel", loadedCells: []
        )
        #expect(persistent.placements.isEmpty)
        #expect(persistent.watchedObjectIDs == [0x300, 0x400])
    }

    /// `Mod.esp` stores a flagged temporary reference in the base plugin's cell (6,-2).
    @Test(.enabled(if: Self.hasDevice)) func findsAFlaggedReferenceALaterPluginAdds() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let base = try ESMFile(data: plugin(
            temporaryRefs: refrRecord(formID: 0x201, base: 0x100),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
        ))
        let cell = ESMFixture.record("CELL", formID: 0x2B, data: cellFields(
            editorID: "TestCell06", grid: (6, -2), flags: 0
        )) + ESMFixture.childGroup(
            parent: 0x2B, groupType: 6, contents: ESMFixture.childGroup(
                parent: 0x2B, groupType: 9,
                contents: fullLOD(refrRecord(formID: 0x0100_0800, base: 0x100))
            )
        )
        let block = ESMFixture.exteriorBlock(
            x: 0, y: -1, groupType: 4,
            contents: ESMFixture.exteriorBlock(x: 0, y: -1, groupType: 5, contents: cell)
        )
        let mod = try ESMFile(data: ESMFixture.tes4(masters: ["Skyrim.esm"])
            + ESMFixture.topGroup(
                "WRLD",
                contents: worldRecord(formID: 0x1A, editorID: "Tamriel")
                    + ESMFixture.childGroup(parent: 0x1A, groupType: 1, contents: block)
            ))
        let device = try #require(Self.device)
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        let textures = try TextureLibrary(fileSystem: vfs, device: device)
        let builder = CellSceneBuilder(
            file: base,
            meshes: MeshLibrary(fileSystem: vfs, device: device, textures: textures),
            textures: textures,
            fileSystem: vfs,
            plugins: [("Skyrim.esm", base), ("Mod.esp", mod)]
        )
        let distant = builder.referenceBuilder.largeReferences.temporaryFullLODPlacements(
            worldspaceEditorID: "Tamriel", loadedCells: []
        )
        #expect(distant.placements.count == 1)
        #expect(distant.watchedObjectIDs == [0x800])
    }
}
