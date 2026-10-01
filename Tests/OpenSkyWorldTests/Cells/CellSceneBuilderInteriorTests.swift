// Interior + door scene-build tests. Synthetic plugin/NIF fixtures only.

import FormatsESMTesting
import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldTesting
import simd
import Testing

extension CellSceneBuilderTests {
    @Test(.enabled(if: Self.hasDevice)) func buildsInteriorDespiteWrongGroupLabels() throws {
        try writeLooseFile("meshes/arch/door.nif", collisionRenderNIF())
        let interiorID: UInt32 = 0x0001_38CA // decimal 80,074 -> block 4 / sub-block 7
        let insideDoor = refrRecord(
            formID: 0x300,
            base: 0x100,
            position: SIMD3(40, 50, 60),
            teleport: TeleportFixture(
                door: 0x200, position: SIMD3(1, 2, 3), rotation: .zero
            )
        )
        let bytes = plugin(
            modelBaseRecords: [
                "DOOR": modelBaseRecord(
                    type: "DOOR", formID: 0x100, modelPath: "arch\\door.nif"
                )
            ],
            interiorRecords: interiorCellGroup(
                formID: interiorID, refs: insideDoor, blockLabel: 9, subBlockLabel: 8
            )
        )
        let device = try #require(Self.device)
        let builder = try makeBuilder(pluginData: bytes, device: device)
        let scene = try builder.buildInteriorScene(cellFormID: FormID(interiorID))

        #expect(scene.location == .interior(FormID(interiorID)))
        #expect(scene.summary.drawnRefCount == 1)
        #expect(scene.renderScene.terrain.isEmpty)
        #expect(scene.renderScene.sky == nil)
        #expect(scene.doors.map(\.reference) == [FormID(0x300)])
        #expect(scene.staticCollision.location == .interior(FormID(interiorID)))
        #expect(scene.staticCollision.stats.shapeCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func resolvesDoorPairIntoOwningCells() throws {
        try writeLooseFile("meshes/arch/door.nif", unitNIF())
        let interiorID: UInt32 = 0x0001_38CA
        let outsideDoor = refrRecord(
            formID: 0x200,
            base: 0x100,
            position: SIMD3(26000, -6000, 100),
            teleport: TeleportFixture(
                door: 0x300,
                position: SIMD3(100, 200, 300),
                rotation: SIMD3(0.1, 0, 1.2)
            )
        )
        let insideDoor = refrRecord(
            formID: 0x300,
            base: 0x100,
            position: SIMD3(100, 200, 300),
            teleport: TeleportFixture(
                door: 0x200,
                position: SIMD3(26000, -6000, 100),
                rotation: SIMD3(0, 0, -0.5)
            )
        )
        let bytes = plugin(
            modelBaseRecords: [
                "DOOR": modelBaseRecord(
                    type: "DOOR", formID: 0x100, modelPath: "arch\\door.nif"
                )
            ],
            extraWorldChildren: persistentActorCell(
                refs: outsideDoor,
                cellID: 0x40,
                editorID: "Persistent"
            ),
            interiorRecords: interiorCellGroup(formID: interiorID, refs: insideDoor)
        )
        let device = try #require(Self.device)
        let builder = try makeBuilder(pluginData: bytes, device: device)

        let exterior = try builder.buildScene(
            worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2
        )
        #expect(exterior.doors.map(\.reference) == [FormID(0x200)])

        let enter = try builder.buildDoorTransition(
            from: FormID(0x200), worldspaceEditorID: "Tamriel"
        )
        #expect(enter.destinationDoor == FormID(0x300))
        #expect(enter.destinationPlacement.position == SIMD3(100, 200, 300))
        #expect(enter.scene.location == .interior(FormID(interiorID)))

        let leave = try builder.buildDoorTransition(
            from: FormID(0x300), worldspaceEditorID: "Tamriel"
        )
        #expect(leave.destinationDoor == FormID(0x200))
        #expect(leave.scene.location == .exterior(CellCoordinate(x: 6, y: -2)))
    }
}
