// The preview draws one record or one placed reference alone, so a record can be
// checked without the rest of its cell. Synthetic plugin only.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import OpenSkyTerrain
import OpenSkyWorldTesting
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct CellSceneBuilderPreviewTests: CellSceneBuilderFixture {
    let dataURL: URL
    private let spot = PlacedReference.Placement(position: SIMD3(10, 20, 30), rotation: .zero)

    init() throws {
        dataURL = try Self.makeDataDirectory()
    }

    private func makeBuilder() throws -> CellSceneBuilder {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let device = try #require(Self.device)
        return try makeBuilder(
            pluginData: plugin(
                temporaryRefs: refrRecord(formID: 0x200, base: 0x100, position: SIMD3(5, 5, 0)),
                statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif")
                    + statRecord(formID: 0x101, modelPath: nil)
            ),
            device: device
        )
    }

    @Test(.enabled(if: Self.hasDevice)) func aStaticDrawsItsModelAtTheSpot() throws {
        let preview = try makeBuilder().previewBuilder
        let subject = try #require(preview.previewObject(base: FormID(0x100), placement: spot))
        #expect(subject.placements.count == 1)
        #expect(subject.failures.isEmpty)
    }

    @Test(.enabled(if: Self.hasDevice)) func aBaseWithoutAModelReportsIt() throws {
        let preview = try makeBuilder().previewBuilder
        let subject = try #require(preview.previewObject(base: FormID(0x101), placement: spot))
        #expect(subject.placements.isEmpty)
        #expect(subject.failures.contains { $0.hasSuffix("no model") })
    }

    @Test(.enabled(if: Self.hasDevice)) func anUnknownBaseHasNoPreview() throws {
        let preview = try makeBuilder().previewBuilder
        #expect(preview.previewObject(base: FormID(0x999), placement: spot) == nil)
        #expect(preview.previewEntryEye(door: FormID(0x999)) == nil)
    }

    @Test(.enabled(if: Self.hasDevice)) func aPlacedReferenceDrawsAtItsOwnSpot() throws {
        let builder = try makeBuilder()
        let scene = try builder.buildScene(worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2)
        let preview = builder.previewBuilder
        let placement = try #require(preview.previewPlacement(of: FormID(0x200), in: scene))
        #expect(placement.position == SIMD3(5, 5, 0))
        #expect(preview.previewSubject(of: FormID(0x200), in: scene)?.placements.count == 1)
        #expect(preview.previewSubject(of: FormID(0x999), in: scene) == nil)
        #expect(preview.previewPlacement(of: FormID(0x999), in: scene) == nil)
        let center = CellGridManager.cellCenter(of: CellCoordinate(x: 6, y: -2))
        #expect(preview.previewSpot(in: scene).position.x == center.x)
    }
}
