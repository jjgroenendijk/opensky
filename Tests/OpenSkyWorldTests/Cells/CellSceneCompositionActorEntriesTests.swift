// One actor key resident in two cells, as the worldspace persistent CELL at
// grid (0,0) produces. Synthetic records only.

@testable import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyRendering
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

struct CellSceneCompositionActorEntriesTests {
    private static let shared: UInt32 = 0xDC5B1
    private static let single: UInt32 = 0x500

    @Test func repeatedActorKeyKeepsTheFirstCellInGridOrder() throws {
        var composition = CellSceneComposition()
        try composition.setCell(
            Self.scene([(Self.shared, 0x101), (Self.single, 0x303)]),
            at: CellCoordinate(x: 0, y: 0)
        )
        try composition.setCell(
            Self.scene([(Self.shared, 0x202)]),
            at: CellCoordinate(x: -2, y: -1)
        )

        let entries = composition.actorEntries()

        #expect(entries.map(\.key) == [Self.key(Self.shared), Self.key(Self.single)])
        #expect(entries.first?.placedActor?.base == FormID(0x202))
    }

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    private static func scene(_ actors: [(UInt32, UInt32)]) throws -> CellScene {
        let entries = try actors.map { objectID, base in
            try RuntimeReferenceEntry(
                key: key(objectID),
                formID: FormID(objectID),
                isPersistent: true,
                record: .actor(placedActor(formID: objectID, base: base))
            )
        }
        return CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "test",
                gridX: 0,
                gridY: 0,
                totalRefCount: 0,
                drawnRefCount: 0,
                unsupportedBaseSkipCount: 0,
                markerSkipCount: 0,
                modelFailureSkipCount: 0,
                malformedRefSkipCount: 0,
                modelCount: 0,
                textureCount: 0,
                missingTextureCount: 0
            ),
            bounds: nil,
            references: RuntimeReferenceIndex(entries: entries)
        )
    }

    private static func placedActor(formID: UInt32, base: UInt32) throws -> PlacedActor {
        var name = Data()
        name.appendUInt32(base)
        let fields = ESMFixture.field("NAME", name) + ESMFixture.field("DATA", Data(count: 24))
        return try PlacedActor(
            record: ESMFixture.parseRecord(ESMFixture.record("ACHR", formID: formID, data: fields))
        )
    }
}
