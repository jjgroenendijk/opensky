// CellSceneBuilder tests over synthetic fixtures only: ESMFixture plugin
// bytes (WRLD/CELL trees + model-base top groups) + NIFFixture
// meshes in a temp-dir VFS. Never extracted game files (AGENTS.md Legal & IP
// boundary). Needs a Metal device (RenderModel upload), gated like
// MeshLibraryTests.
//
// The fixture half of this suite -- the type itself, the temp-dir VFS and every
// record and mesh builder -- is `openskyTestSupport/CellSceneBuilderFixture.swift`,
// because the M11 real-data acceptance suite builds the same synthetic cell
// (issue #418).

import Foundation
import Metal
@testable import opensky
import simd
import Testing

extension CellSceneBuilderTests {
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
