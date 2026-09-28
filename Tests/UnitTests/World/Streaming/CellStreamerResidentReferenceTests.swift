// Resident runtime-reference accounting for the streamer (issue #162, roadmap
// item 10.1.5): the number the sidebar readout shows for "references in
// memory".
//
// Split from CellStreamerRuntimeStateTests so both stay inside the type-body
// limit. Scenes are built here rather than through
// `CellStreamerTests.cellScene` because that fixture retains no references, and
// `CellScene.references` is immutable once built.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct CellStreamerResidentReferenceTests {
    @Test
    func residentReferenceCountFollowsScenesInAndOutOfResidency() throws {
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)
        let cell = CellStreamerTests.coordinate(0, 0)
        let camera = CellGridManager.cellCenter(of: cell)
        #expect(streamer.residentReferenceCount == 0)

        streamer.update(cameraPosition: camera)
        let scene = try Self.scene(references: Self.referenceIndex(count: 3))
        runner.complete(cell, with: .success(scene))
        streamer.update(cameraPosition: camera)
        #expect(streamer.residentCellCount == 1)
        #expect(streamer.residentReferenceCount == 3)

        // Walking far enough away unloads the cell, and the count follows
        // residency rather than history.
        streamer.update(cameraPosition: CellGridManager.cellCenter(
            of: CellStreamerTests.coordinate(40, 40)
        ))
        #expect(streamer.residentCellCount == 0)
        #expect(streamer.residentReferenceCount == 0)
    }

    @Test
    func anEmptyIndexContributesNothing() {
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)
        let cell = CellStreamerTests.coordinate(0, 0)
        let camera = CellGridManager.cellCenter(of: cell)

        streamer.update(cameraPosition: camera)
        runner.complete(cell, with: .success(Self.scene(references: .empty)))
        streamer.update(cameraPosition: camera)

        #expect(streamer.residentCellCount == 1)
        #expect(streamer.residentReferenceCount == 0)
    }

    // MARK: - Fixtures

    private static func scene(references: RuntimeReferenceIndex) -> CellScene {
        CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "test", gridX: 0, gridY: 0,
                totalRefCount: 0, drawnRefCount: 0,
                unsupportedBaseSkipCount: 0, markerSkipCount: 0,
                modelFailureSkipCount: 0, malformedRefSkipCount: 0,
                modelCount: 0, textureCount: 0, missingTextureCount: 0
            ),
            bounds: (SIMD3(0, 0, 0), SIMD3(10, 10, 10)),
            references: references
        )
    }

    /// `count` synthetic REFR placements, indexed the way a real cell build
    /// indexes them.
    private static func referenceIndex(count: UInt32) throws -> RuntimeReferenceIndex {
        var entries: [RuntimeReferenceEntry] = []
        for objectID in 1 ... count {
            var name = Data()
            name.appendUInt32(0x100)
            let bytes = ESMFixture.record(
                "REFR",
                formID: objectID,
                data: ESMFixture.field("NAME", name)
                    + ESMFixture.field("DATA", Data(count: 24))
            )
            let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
            guard case let .record(record)? = children.first else {
                throw ESMError.malformed("fixture did not produce a record")
            }
            try entries.append(RuntimeReferenceEntry(
                key: .plugin(name: "skyrim.esm", objectID: objectID),
                formID: FormID(objectID),
                isPersistent: false,
                record: .reference(PlacedReference(record: record))
            ))
        }
        return RuntimeReferenceIndex(entries: entries)
    }
}
