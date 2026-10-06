// A walk or a turn starts where the actor is drawn: its movement pose, then a
// saved transform, then the placed record. Synthetic ACHR only.

import FormatsTesting
import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
struct NPCStandingTransformTests {
    private let cell = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))
    private let saved = ReferenceTransformOverride(
        position: SIMD3(300, 50, 0), rotation: SIMD3(0, 0, 1), scale: 1.5
    )

    @Test func withoutASavedPoseTheActorStartsAtItsRecord() throws {
        let entry = try Self.actorEntry(at: SIMD3(10, 0, 0))
        let standing = NPCMovementRuntime().standingTransform(of: entry, in: .empty)
        #expect(standing.position == SIMD3(10, 0, 0))
        #expect(standing.scale == 1)
    }

    @Test func theFirstWalkAfterALoadStartsAtTheSavedPose() throws {
        let entry = try Self.actorEntry(at: SIMD3(10, 0, 0))
        let store = WorldStateStore()
        store.set(saved, for: entry.key, in: cell)
        var runtime = NPCMovementRuntime()
        let standing = runtime.standingTransform(of: entry, in: store.snapshot())
        #expect(standing.position == saved.position)
        #expect(standing.rotation == saved.rotation)
        #expect(standing.scale == saved.scale)

        let target = saved.position + SIMD3(100, 0, 0)
        let started = runtime.start(NPCMoveStart(
            actor: entry.key,
            formID: entry.formID,
            placement: standing.placement,
            scale: standing.scale,
            capsule: .standard,
            configuration: .synthetic,
            path: NPCMovementRuntimeTests.path(waypoints: [target], target: target)
        ))
        #expect(started)
        let delta = try #require(runtime.instanceDeltas()[entry.formID.rawValue])
        #expect(simd_distance(delta.columns.3, SIMD4(0, 0, 0, 1)) < 0.001)
    }

    @Test func aMovingActorStartsWhereItNowStands() throws {
        let entry = try Self.actorEntry(at: SIMD3(10, 0, 0))
        var runtime = NPCMovementRuntime()
        runtime.face(NPCFaceStart(
            actor: entry.key,
            formID: entry.formID,
            placement: PlacedReference.Placement(position: SIMD3(20, 0, 0), rotation: .zero),
            scale: 1,
            target: SIMD3(20, 100, 0)
        ))
        let store = WorldStateStore()
        store.set(saved, for: entry.key, in: cell)
        let standing = runtime.standingTransform(of: entry, in: store.snapshot())
        #expect(standing.position == SIMD3(20, 0, 0))
    }

    private static func actorEntry(at position: SIMD3<Float>) throws -> RuntimeReferenceEntry {
        var data = Data()
        for value in [position.x, position.y, position.z, 0, 0, 0] {
            data.appendFloat32(value)
        }
        var name = Data()
        name.appendUInt32(0x900)
        let fields = ESMFixture.field("NAME", name) + ESMFixture.field("DATA", data)
        let bytes = ESMFixture.record("ACHR", formID: 0x100, data: fields)
        let record = try ESMFixture.parseRecord(bytes)
        return try RuntimeReferenceEntry(
            key: .plugin(name: "skyrim.esm", objectID: FormID(0x100).objectID),
            formID: FormID(0x100),
            isPersistent: true,
            record: .actor(PlacedActor(record: record))
        )
    }
}
