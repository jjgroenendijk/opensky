// The distant ring draws temporary Is Full LOD references from cells that are not loaded.
// Synthetic plugin only.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
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
    private func fullLOD(_ record: Data) -> Data {
        var bytes = record
        let start = bytes.startIndex + 8
        let flags = PlacedReference.fullLODFlag
        for byte in 0 ..< 4 {
            bytes[start + byte] |= UInt8(truncatingIfNeeded: flags >> (8 * UInt32(byte)))
        }
        return bytes
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
        let world = try builder.worldChildrenGroup(editorID: "Tamriel", localized: false)
        #expect(builder.temporaryFullLODCells(in: world) == [CellCoordinate(x: 6, y: -2)])

        let distant = builder.temporaryFullLODPlacements(
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
        let distant = builder.temporaryFullLODPlacements(
            worldspaceEditorID: "Tamriel", loadedCells: [CellCoordinate(x: 6, y: -2)]
        )
        #expect(distant.placements.isEmpty)
    }

    @Test(.enabled(if: Self.hasDevice)) func anUnflaggedCellIsNotIndexed() throws {
        let builder = try makeBuilder(temporaryRefs: refrRecord(formID: 0x201, base: 0x100))
        let world = try builder.worldChildrenGroup(editorID: "Tamriel", localized: false)
        #expect(builder.temporaryFullLODCells(in: world).isEmpty)
    }
}
