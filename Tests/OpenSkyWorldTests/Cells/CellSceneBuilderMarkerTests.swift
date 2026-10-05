// Editor markers placed in a cell are not drawn, as in the game. Both signals are
// covered: the base record's `Is Marker` flag and `EditorMarker` mesh shapes.

import FormatsESMTesting
import FormatsMeshTesting
import Foundation
import OpenSkyFormatsESM
import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldInterface
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct CellSceneBuilderMarkerTests: CellSceneBuilderFixture {
    let dataURL: URL

    init() throws {
        dataURL = try Self.makeDataDirectory()
    }

    private static let markerFlag: UInt32 = 0x0080_0000

    private func markerOnlyNIF() -> Data {
        NIFFixture.file(
            blocks: [
                .init("BSFadeNode", NIFFixture.niNode(children: [1])),
                .init("BSTriShape", NIFFixture.bsTriShape(
                    prefix: NIFFixture.avObjectPrefix(nameIndex: 0),
                    attributes: Self.staticAttributes,
                    strideDwords: Self.staticStrideDwords,
                    vertexRecords: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 1)]
                        .map(vertexRecord(position:)),
                    triangles: [0, 1, 2]
                ))
            ],
            strings: ["EditorMarker"]
        )
    }

    @Test(.enabled(if: Self.hasDevice)) func flaggedBasesAreNotDrawn() throws {
        try writeLooseFile("meshes/markerxheading.nif", unitNIF())
        try writeLooseFile("meshes/furniture/counterleanmarker.nif", unitNIF())
        let model = { (path: String) in ESMFixture.field("MODL", ESMFixture.zstring(path)) }
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100)
                + refrRecord(formID: 0x201, base: 0x101),
            statRecords: ESMFixture.record(
                "STAT", formID: 0x100, flags: Self.markerFlag, data: model("MarkerXHeading.nif")
            ),
            modelBaseRecords: ["FURN": ESMFixture.record(
                "FURN", formID: 0x101, flags: Self.markerFlag,
                data: model("Furniture\\CounterLeanMarker.nif")
            )]
        ))
        #expect(scene.summary.markerSkipCount == 2)
        #expect(scene.summary.drawnRefCount == 0)
        #expect(scene.summary.modelFailureSkipCount == 0)
        // The furniture stays usable; only its marker mesh is hidden.
        #expect(scene.interactions[FormID(0x201)]?.action == .use)
    }

    @Test(.enabled(if: Self.hasDevice)) func markerOnlyMeshCountsAsMarker() throws {
        try writeLooseFile("meshes/furniture/chairinvisiblesingle.nif", markerOnlyNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100),
            modelBaseRecords: ["FURN": modelBaseRecord(
                type: "FURN", formID: 0x100, modelPath: "Furniture\\ChairInvisibleSingle.nif"
            )]
        ))
        #expect(scene.summary.markerSkipCount == 1)
        #expect(scene.summary.modelFailureSkipCount == 0)
        #expect(scene.renderScene.drawCount == 0)
        #expect(scene.interactions[FormID(0x200)] != nil)
    }
}
