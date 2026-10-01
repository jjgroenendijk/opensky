// The worldspace persistent CELL sits directly in the world children group and
// carries XCLC (0,0), like the real block cell at (0,0). Grid lookups must skip
// it; its references map into cells by position. Synthetic fixtures only.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldState
import simd
import Testing

extension CellSceneBuilderTests {
    /// Cell (0,0) spans x and y 0..4096; cell (6,-2) spans x 24576..28672, y -8192..-4096.
    private func persistentCellPlugin(
        grid: (x: Int32, y: Int32),
        temporaryRefs: Data = Data(),
        persistentRefs: Data
    ) -> Data {
        plugin(
            cellEditorID: "BlockCell",
            grid: grid,
            temporaryRefs: temporaryRefs,
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\wall.nif"),
            modelBaseRecords: actorChainRecords(npc: 0x800),
            extraWorldChildren: persistentActorCell(refs: persistentRefs)
        )
    }

    @Test(.enabled(if: Self.hasDevice))
    func gridZeroBuildsTheBlockCellNotThePersistentCell() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        try writeLooseFile("meshes/torso_m.nif", unitNIF())
        let bytes = persistentCellPlugin(
            grid: (0, 0),
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100, position: SIMD3(100, 100, 0)),
            persistentRefs: achrRecord(
                formID: 0x900,
                base: 0x800,
                position: SIMD3(25000, -6000, 10)
            )
                + refrRecord(formID: 0x201, base: 0x100, position: SIMD3(25000, -6000, 0))
        )
        let scene = try build(pluginData: bytes, gridX: 0, gridY: 0)

        #expect(scene.summary.cellName == "BlockCell")
        #expect(scene.summary.totalRefCount == 1)
        #expect(scene.summary.drawnRefCount == 1)
        #expect(scene.summary.actorCount == 0)
    }

    @Test(.enabled(if: Self.hasDevice))
    func persistentCellAloneIsNotGridZero() throws {
        let bytes = persistentCellPlugin(
            grid: (6, -2),
            persistentRefs: refrRecord(formID: 0x201, base: 0x100, position: SIMD3(100, 100, 0))
        )
        #expect(throws: CellSceneError.self) {
            try build(pluginData: bytes, gridX: 0, gridY: 0)
        }
        let models = try ExteriorCellModelCatalog(file: ESMFile(data: bytes))
        #expect(throws: CellSceneError.self) {
            try models.models(worldspaceEditorID: "Tamriel", gridX: 0, gridY: 0)
        }
    }

    @Test(.enabled(if: Self.hasDevice))
    func persistentReferenceMapsIntoOwningCellByPosition() throws {
        try writeLooseFile("meshes/arch/wall.nif", unitNIF())
        let bytes = persistentCellPlugin(
            grid: (6, -2),
            persistentRefs: refrRecord(formID: 0x201, base: 0x100, position: SIMD3(25000, -6000, 0))
                + refrRecord(formID: 0x202, base: 0x100, position: SIMD3(29000, -6000, 0))
        )
        let scene = try build(pluginData: bytes)

        #expect(scene.summary.totalRefCount == 1)
        #expect(scene.summary.drawnRefCount == 1)
        #expect(scene.references.entry(for: FormID(0x201))?.isPersistent == true)
        #expect(scene.references.entry(for: FormID(0x202)) == nil)
    }
}
