// Where a cape's actor stands and how its cape bone is posed: a loaded, posed actor gives a
// frame, and an actor the world cannot place gives none. See docs/engine/cape-cloth.md.

import Metal
import OpenSkyActorAdapters
import OpenSkyFormatsCore
import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyPlayer
@testable import OpenSkyRenderResources
import OpenSkySessionTesting
import OpenSkyTagsTesting
import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import Testing

@MainActor
@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct ClothWorldAdapterTests {
    private static let bone = "NPC Spine2 [Spn2]"

    nonisolated private static var hasDevice: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    private static func cloth(actor: FormID) throws -> ClothPlayback {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let mesh = try RenderMesh(device: device, mesh: Mesh(
            name: ClothPlayback.shapeName, transform: matrix_identity_float4x4,
            positions: [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(0, 0, -10)],
            normals: [], tangents: [], bitangents: [], uvs: [], colors: [],
            indices: [0, 1, 2], materialSlot: 0
        ))
        return try ClothPlayback(
            actor: actor, bone: bone, mesh: mesh,
            deltas: FaceMorphBuffer(device: device, simulating: mesh), body: (16, 120)
        )
    }

    @Test(.enabled(if: Self.hasDevice))
    func aLoadedPosedActorGivesItsCapeAFrame() throws {
        let host = ActorHost()
        let adapter = ClothWorldAdapter(game: host, stage: nil)
        let cloth = try Self.cloth(actor: FormID(0x600))
        #expect(adapter.clothFrame(for: cloth) == nil, "the actor is not loaded")
        #expect(adapter.clothFrameMiss(for: cloth) == .actorNotLoaded)
        let entry = try PackageRuntimeFixture.residentActor(0x600, base: 0x700)
        host.fakeStreamer.referenceEntryFormIDResult = entry
        var spine = matrix_identity_float4x4
        spine.columns.3.z = 100
        host.poses[entry.key] = [Self.bone: spine]
        let frame = try #require(adapter.clothFrame(for: cloth))
        #expect(adapter.clothFrameMiss(for: cloth) == nil)
        #expect(frame.boneToActor.columns.3.z == 100)
        #expect(frame.scale == 1)
        #expect(frame.calves.isEmpty, "an actor without a ragdoll has no calf capsules")
        #expect(host.fakeRagdoll.ragdollDefinitionCalls == [entry.key])
    }

    @Test(.enabled(if: Self.hasDevice))
    func thePlayersCapeWaitsForThePlayerBody() throws {
        let adapter = ClothWorldAdapter(game: ActorHost(), stage: nil)
        let cloth = try Self.cloth(actor: PlayerBody.actorFormID)
        #expect(adapter.clothFrame(for: cloth) == nil)
        #expect(adapter.clothFrameMiss(for: cloth) == .noPlayerBody)
    }
}
