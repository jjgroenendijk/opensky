// Trigger-volume collection into CellScene (issue #173): the XPRM primitive
// source, the SkyrimLayer 12 NIF-body source, the primitive types that are
// deliberately excluded, and the static-collision accounting that must not
// move. Synthetic ESM + NIF bytes only; no game content.

import Foundation
import Metal
@testable import opensky
import simd
import Testing

extension CellSceneBuilderTests {
    // MARK: - XPRM primitives

    @Test(.enabled(if: Self.hasDevice)) func placesPrimitiveBoxAsOneTriggerVolume() throws {
        let scene = try build(pluginData: plugin(
            temporaryRefs: primitiveRefrRecord(
                formID: 0x200,
                base: 0x100,
                position: SIMD3(100, 200, 300),
                scale: 2,
                primitive: PrimitiveFixture(halfExtents: SIMD3(10, 20, 30), type: .box)
            ),
            statRecords: statRecord(formID: 0x100, modelPath: nil)
        ))
        let triggers = scene.triggerVolumes
        #expect(triggers.location == .exterior(CellCoordinate(x: 6, y: -2)))
        #expect(triggers.stats.primitiveVolumeCount == 1)
        #expect(triggers.stats.meshVolumeCount == 0)
        let volume = try #require(triggers.volumes.first)
        #expect(volume.reference == .plugin(name: "skyrim.esm", objectID: 0x200))
        #expect(volume.formID == FormID(0x200))
        guard case let .box(halfExtents) = volume.geometry else {
            Issue.record("XPRM box did not become box geometry")
            return
        }
        #expect(halfExtents == SIMD3(10, 20, 30))
        // XSCL 2 doubles the half-extents around the reference's position.
        #expect(volume.bounds.min == SIMD3<Float>(100 - 20, 200 - 40, 300 - 60))
        #expect(volume.bounds.max == SIMD3<Float>(100 + 20, 200 + 40, 300 + 60))
    }

    @Test(.enabled(if: Self.hasDevice)) func placesPrimitiveSphereWithTheStoredRadius() throws {
        let scene = try build(pluginData: plugin(
            temporaryRefs: primitiveRefrRecord(
                formID: 0x200,
                base: 0x100,
                position: SIMD3(0, 0, 50),
                // Vanilla stores one radius in all three axes; the decoder
                // reads .x (PlacedReferenceXPRMRealDataTests).
                primitive: PrimitiveFixture(halfExtents: SIMD3(64, 64, 64), type: .sphere)
            ),
            statRecords: statRecord(formID: 0x100, modelPath: nil)
        ))
        let volume = try #require(scene.triggerVolumes.volumes.first)
        guard case let .sphere(radius) = volume.geometry else {
            Issue.record("XPRM sphere did not become sphere geometry")
            return
        }
        #expect(radius == 64)
        #expect(volume.bounds.min == SIMD3<Float>(-64, -64, -14))
        #expect(scene.triggerVolumes.stats.primitiveVolumeCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func excludesPortalBoxLineAndNonePrimitives() throws {
        let excluded: [PlacedReference.PrimitiveType] = [.none, .portalBox, .line]
        var refs = Data()
        for (offset, type) in excluded.enumerated() {
            refs += primitiveRefrRecord(
                formID: UInt32(0x200 + offset),
                base: 0x100,
                primitive: PrimitiveFixture(halfExtents: SIMD3(10, 10, 10), type: type)
            )
        }
        let scene = try build(pluginData: plugin(
            temporaryRefs: refs,
            statRecords: statRecord(formID: 0x100, modelPath: nil)
        ))
        #expect(scene.triggerVolumes.volumes.isEmpty)
        #expect(scene.triggerVolumes.stats.excludedPrimitiveCount == 3)
        #expect(scene.triggerVolumes.stats.volumeCount == 0)
    }

    @Test(.enabled(if: Self.hasDevice)) func buildsNoTriggerVolumesWithoutEitherSource() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\solid.nif")
        ))
        #expect(scene.triggerVolumes.volumes.isEmpty)
        #expect(scene.triggerVolumes.stats == TriggerVolumeStats())
        #expect(scene.staticCollision.stats.shapeCount == 1)
    }

    // MARK: - Layer 12 NIF bodies

    @Test(.enabled(if: Self.hasDevice))
    func routesLayerTwelveBodiesOutOfStaticCollision() throws {
        try writeLooseFile("meshes/arch/solid.nif", collisionRenderNIF())
        try writeLooseFile("meshes/arch/trigger.nif", triggerCollisionNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x200, base: 0x100)
                + refrRecord(formID: 0x201, base: 0x101, position: SIMD3(500, 0, 0)),
            statRecords: statRecord(formID: 0x100, modelPath: "arch\\solid.nif")
                + statRecord(formID: 0x101, modelPath: "arch\\trigger.nif")
        ))
        // The solid body is the only one that stays physical.
        #expect(scene.staticCollision.stats.shapeCount == 1)
        #expect(scene.staticCollision.shapes.map(\.reference) == [FormID(0x200)])
        let volume = try #require(scene.triggerVolumes.volumes.first)
        #expect(scene.triggerVolumes.volumes.count == 1)
        #expect(volume.formID == FormID(0x201))
        #expect(volume.reference == .plugin(name: "skyrim.esm", objectID: 0x201))
        #expect(scene.triggerVolumes.stats.meshVolumeCount == 1)
        // Sphere of Havok radius 1 placed at x = 500.
        let radius = NIFCollisionModel.havokToEngineScale
        #expect(abs(volume.bounds.min.x - (500 - radius)) < 0.01)
    }

    @Test(.enabled(if: Self.hasDevice))
    func keepsFilteredBodyCountUnchangedForTriggerBodies() throws {
        try writeLooseFile("meshes/arch/trigger.nif", triggerCollisionNIF())
        let scene = try build(pluginData: plugin(
            temporaryRefs: refrRecord(formID: 0x201, base: 0x101),
            statRecords: statRecord(formID: 0x101, modelPath: "arch\\trigger.nif")
        ))
        // A trigger body is still a non-player-solid body, so it keeps
        // counting as filtered exactly as it did before it was collected —
        // the CLI grid acceptance asserts on this number.
        #expect(scene.staticCollision.stats.bodyCount == 1)
        #expect(scene.staticCollision.stats.filteredBodyCount == 1)
        #expect(scene.staticCollision.stats.shapeCount == 0)
        #expect(scene.triggerVolumes.stats.meshVolumeCount == 1)
    }

    // MARK: - Fixtures

    struct PrimitiveFixture {
        let halfExtents: SIMD3<Float>
        let type: PlacedReference.PrimitiveType
    }

    /// A REFR carrying an XPRM payload, which `refrRecord` cannot express.
    /// Layout: float[3] bounds, float[3] color, float unknown, uint32 type
    /// (docs/formats/records.md).
    func primitiveRefrRecord(
        formID: UInt32,
        base: UInt32,
        position: SIMD3<Float> = .zero,
        scale: Float? = nil,
        primitive: PrimitiveFixture
    ) -> Data {
        var name = Data()
        name.appendUInt32(base)
        var fields = ESMFixture.field("NAME", name)
        var data = Data()
        for value in [position.x, position.y, position.z, 0, 0, 0] {
            data.appendFloat32(value)
        }
        fields += ESMFixture.field("DATA", data)
        if let scale {
            var xscl = Data()
            xscl.appendFloat32(scale)
            fields += ESMFixture.field("XSCL", xscl)
        }
        var xprm = Data()
        for value in [
            primitive.halfExtents.x, primitive.halfExtents.y, primitive.halfExtents.z,
            1, 0, 0, 0.15
        ] {
            xprm.appendFloat32(value)
        }
        xprm.appendUInt32(primitive.type.rawValue)
        fields += ESMFixture.field("XPRM", xprm)
        return ESMFixture.record("REFR", formID: formID, data: fields)
    }

    /// Collision-only NIF whose single rigid body sits on SkyrimLayer 12, the
    /// trigger layer, in both duplicate Havok filters.
    func triggerCollisionNIF() -> Data {
        NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(
                shape: 3, worldLayer: 12, rigidLayer: 12
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1))
        ])
    }
}

/// Fan-out of the trigger queries across resident cells (issue #173). No Metal
/// device needed: the scenes are assembled directly from placed volumes.
struct TriggerVolumeCompositionTests {
    private func volume(_ objectID: UInt32, at center: SIMD3<Float>) throws -> TriggerVolume {
        try #require(TriggerVolume.placed(
            reference: .plugin(name: "skyrim.esm", objectID: objectID),
            formID: FormID(objectID),
            transform: MatrixMath.translation(center),
            geometry: .box(halfExtents: SIMD3(repeating: 50))
        ))
    }

    private func scene(_ triggers: TriggerVolumeSet) -> CellScene {
        CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "trigger-test",
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
            triggerVolumes: triggers
        )
    }

    private func composition() throws -> CellSceneComposition {
        var composition = CellSceneComposition()
        for x in Int32(0) ... 1 {
            let coordinate = CellCoordinate(x: x, y: 0)
            var stats = TriggerVolumeStats()
            stats.primitiveVolumeCount = 1
            try composition.setCell(
                scene(TriggerVolumeSet(
                    location: .exterior(coordinate),
                    volumes: [volume(UInt32(0x200 + x), at: SIMD3(Float(x) * 1000, 0, 0))],
                    stats: stats
                )),
                at: coordinate
            )
        }
        return composition
    }

    @Test func queriesEveryResidentCellInCoordinateOrder() throws {
        let composition = try composition()
        let all = ModelBounds(
            min: SIMD3(repeating: -5000), max: SIMD3(repeating: 5000)
        )
        #expect(composition.triggerCandidates(overlapping: all).map(\.formID)
            == [FormID(0x200), FormID(0x201)])
        #expect(composition.triggerStats().primitiveVolumeCount == 2)
        #expect(composition.triggerStats().volumeCount == 2)
    }

    @Test func findsOnlyTheVolumeTheCapsuleStandsIn() throws {
        let composition = try composition()
        let inside = composition.triggerVolumes(
            intersecting: .standard, at: SIMD3(1000, 0, 0)
        )
        #expect(inside.map(\.formID) == [FormID(0x201)])
        let outside = composition.triggerVolumes(
            intersecting: .standard, at: SIMD3(500, 0, 0)
        )
        #expect(outside.isEmpty)
    }
}
