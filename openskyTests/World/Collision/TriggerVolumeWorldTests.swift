// Trigger-volume broadphase + capsule narrowphase over synthetic engine values
// only. No game content, file parsing, or Metal device required.

@testable import opensky
import simd
import Testing

struct TriggerVolumeWorldTests {
    private let capsule = PlayerCapsule.standard

    private func boxVolume(
        objectID: UInt32,
        center: SIMD3<Float>,
        halfExtents: SIMD3<Float> = SIMD3(repeating: 64)
    ) -> TriggerVolume? {
        TriggerVolume.placed(
            reference: .plugin(name: "trigger.esm", objectID: objectID),
            formID: FormID(objectID),
            transform: MatrixMath.translation(center),
            geometry: .box(halfExtents: halfExtents)
        )
    }

    private func sphereVolume(
        objectID: UInt32,
        center: SIMD3<Float>,
        radius: Float
    ) -> TriggerVolume? {
        TriggerVolume.placed(
            reference: .plugin(name: "trigger.esm", objectID: objectID),
            formID: FormID(objectID),
            transform: MatrixMath.translation(center),
            geometry: .sphere(radius: radius)
        )
    }

    @Test func emptySetHasNoVolumesNoNodesAndNoCandidates() {
        let set = TriggerVolumeSet.empty
        #expect(set.location == nil)
        #expect(set.volumes.isEmpty)
        #expect(set.indexNodeCount == 0)
        let everywhere = ModelBounds(
            min: SIMD3(repeating: -100_000),
            max: SIMD3(repeating: 100_000)
        )
        #expect(set.candidates(overlapping: everywhere).isEmpty)
        #expect(set.volumes(intersecting: capsule, at: .zero).isEmpty)
    }

    @Test func broadphaseBuildsBVHAndReturnsCandidatesInStableOrder() throws {
        let volumes = try (0 ..< 8).map { index in
            try #require(boxVolume(
                objectID: UInt32(index + 1),
                center: SIMD3(Float(index) * 512, 0, 0),
                halfExtents: SIMD3(repeating: 64)
            ))
        }
        let set = TriggerVolumeSet(
            location: .exterior(CellCoordinate(x: 0, y: 0)),
            volumes: volumes
        )
        #expect(set.indexNodeCount > 1)

        // Volume n spans x = 512n +/- 64, so this range covers volumes 2 and 3
        // (object identifiers 3 and 4) and nothing else.
        let candidates = set.candidates(overlapping: ModelBounds(
            min: SIMD3(1000, -8, -8),
            max: SIMD3(1500, 8, 8)
        ))
        #expect(candidates.map(\.formID) == [FormID(3), FormID(4)])
        #expect(candidates.map(\.reference) == [
            .plugin(name: "trigger.esm", objectID: 3),
            .plugin(name: "trigger.esm", objectID: 4)
        ])
    }

    @Test func broadphaseRejectsBoundsThatMissEveryVolume() throws {
        let volume = try #require(boxVolume(objectID: 1, center: SIMD3(0, 0, 0)))
        let set = TriggerVolumeSet(location: nil, volumes: [volume])
        let far = ModelBounds(min: SIMD3(5000, 5000, 5000), max: SIMD3(5100, 5100, 5100))
        #expect(set.candidates(overlapping: far).isEmpty)
        #expect(set.volumes(intersecting: capsule, at: SIMD3(5000, 5000, 5000)).isEmpty)
    }

    @Test func capsuleStandingInsideBoxIntersects() throws {
        let volume = try #require(boxVolume(
            objectID: 1,
            center: SIMD3(0, 0, 64),
            halfExtents: SIMD3(128, 128, 64)
        ))
        let set = TriggerVolumeSet(location: nil, volumes: [volume])
        let hits = set.volumes(intersecting: capsule, at: .zero)
        #expect(hits.map(\.formID) == [FormID(1)])
    }

    @Test func capsuleOutsideBoxDoesNotIntersect() throws {
        let volume = try #require(boxVolume(
            objectID: 1,
            center: SIMD3(0, 0, 64),
            halfExtents: SIMD3(64, 64, 64)
        ))
        let set = TriggerVolumeSet(location: nil, volumes: [volume])
        // Feet 200 units out on X: the nearest box face is at x = 64, so the
        // gap is 136 units, well beyond the 24-unit capsule radius.
        #expect(set.volumes(intersecting: capsule, at: SIMD3(200, 0, 0)).isEmpty)
    }

    @Test func capsuleGrazingABoxFaceIntersectsAndClearingItDoesNot() throws {
        let volume = try #require(boxVolume(
            objectID: 1,
            center: SIMD3(0, 0, 64),
            halfExtents: SIMD3(64, 64, 64)
        ))
        let set = TriggerVolumeSet(location: nil, volumes: [volume])
        // Face at x = 64. Capsule radius 24, so a centre at x = 85 leaves a
        // 21-unit gap (inside) and x = 95 leaves 31 units (outside).
        #expect(set.volumes(intersecting: capsule, at: SIMD3(85, 0, 0)).count == 1)
        #expect(set.volumes(intersecting: capsule, at: SIMD3(95, 0, 0)).isEmpty)
    }

    @Test func rotatedBoxIsTestedInItsOwnSpace() throws {
        // A thin slab rotated 90 degrees about Z: its long axis ends up on X,
        // so a capsule far out on X is inside while the same distance on Y is
        // not. An axis-aligned test would get both wrong.
        let rotation = MatrixMath.translation(SIMD3(0, 0, 64))
            * MatrixMath.rotationZ(radians: .pi / 2)
        let volume = try #require(TriggerVolume.placed(
            reference: .plugin(name: "trigger.esm", objectID: 1),
            formID: FormID(1),
            transform: rotation,
            geometry: .box(halfExtents: SIMD3(16, 256, 64))
        ))
        let set = TriggerVolumeSet(location: nil, volumes: [volume])
        #expect(set.volumes(intersecting: capsule, at: SIMD3(200, 0, 0)).count == 1)
        #expect(set.volumes(intersecting: capsule, at: SIMD3(0, 200, 0)).isEmpty)
    }

    @Test func sphereVolumeUsesRadialDistance() throws {
        let volume = try #require(sphereVolume(objectID: 1, center: SIMD3(0, 0, 64), radius: 100))
        let set = TriggerVolumeSet(location: nil, volumes: [volume])
        #expect(set.volumes(intersecting: capsule, at: SIMD3(100, 0, 0)).count == 1)
        #expect(set.volumes(intersecting: capsule, at: SIMD3(200, 0, 0)).isEmpty)
    }

    @Test func capsuleVolumeUsesSegmentToSegmentDistance() throws {
        // A horizontal obstacle capsule along Y at player chest height.
        let volume = try #require(TriggerVolume.placed(
            reference: .plugin(name: "trigger.esm", objectID: 1),
            formID: FormID(1),
            transform: MatrixMath.translation(SIMD3(0, 0, 64)),
            geometry: .capsule(first: SIMD3(0, -256, 0), second: SIMD3(0, 256, 0), radius: 32)
        ))
        let set = TriggerVolumeSet(location: nil, volumes: [volume])
        #expect(set.volumes(intersecting: capsule, at: SIMD3(50, 100, 0)).count == 1)
        #expect(set.volumes(intersecting: capsule, at: SIMD3(120, 100, 0)).isEmpty)
        // Past the obstacle's end cap on Y, the segment distance grows again.
        #expect(set.volumes(intersecting: capsule, at: SIMD3(0, 400, 0)).isEmpty)
    }

    @Test func triangleSoupFallsBackToItsConservativeWorldBox() throws {
        // One right triangle filling half of a wide, flat square. The capsule
        // sits in the empty half: the documented AABB approximation reports a
        // hit even though no triangle is near, which is the intended
        // conservative behaviour for a mesh trigger.
        let vertices: [SIMD3<Float>] = [
            SIMD3(-256, -256, 0), SIMD3(256, -256, 0), SIMD3(-256, 256, 0)
        ]
        let volume = try #require(TriggerVolume.placed(
            reference: .plugin(name: "trigger.esm", objectID: 1),
            formID: FormID(1),
            transform: matrix_identity_float4x4,
            geometry: .triangleSoup(vertices: vertices, indices: [0, 1, 2])
        ))
        #expect(volume.bounds.min.x == -256)
        #expect(volume.bounds.max.y == 256)
        let set = TriggerVolumeSet(location: nil, volumes: [volume])
        #expect(set.volumes(intersecting: capsule, at: SIMD3(200, 200, 0)).count == 1)
        #expect(set.volumes(intersecting: capsule, at: SIMD3(2000, 2000, 0)).isEmpty)
    }

    @Test func degenerateGeometryProducesNoVolume() {
        // No index addresses an existing vertex, so no partition and no bounds.
        let volume = TriggerVolume.placed(
            reference: .plugin(name: "trigger.esm", objectID: 1),
            formID: FormID(1),
            transform: matrix_identity_float4x4,
            geometry: .triangleSoup(vertices: [], indices: [0, 1, 2])
        )
        #expect(volume == nil)
    }

    @Test func placementPushesLocalBoundsThroughTheReferenceTransform() throws {
        let volume = try #require(boxVolume(
            objectID: 9,
            center: SIMD3(1000, -2000, 300),
            halfExtents: SIMD3(10, 20, 30)
        ))
        #expect(volume.bounds.min == SIMD3<Float>(990, -2020, 270))
        #expect(volume.bounds.max == SIMD3<Float>(1010, -1980, 330))
        #expect(volume.formID == FormID(9))
    }
}
