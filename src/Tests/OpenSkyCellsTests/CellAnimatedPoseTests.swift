// An animated object and a posed copy each publish their pose through the buffer their
// playback writes, so the coordinator and the renderer read the same bones.

@testable import OpenSkyCells
import OpenSkyEngineTesting
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyObjectAnimation
import OpenSkyPlayer
@testable import OpenSkyRendering
import simd
import Testing

struct CellAnimatedPoseTests {
    private static func instance() -> ResolvedInstance {
        ResolvedInstance(
            sortKey: "clutter\\wheel.nif", formID: 0x500, modelPath: "clutter\\wheel.nif",
            model: RenderModel(meshes: [], renderMaterials: []),
            surface: ModelSurfaceOverride(diffuseTexture: nil, normalTexture: nil, tint: nil),
            transform: matrix_identity_float4x4
        )
    }

    @Test func anAnimatedObjectSharesItsPlaybackBuffer() throws {
        let asset = try BehaviorProjectFixture.asset()
        let built = CellSceneBuilder.CellAnimatedObjectBuilder.animatedObject(
            Self.instance(),
            asset: asset,
            nodes: nil
        )
        let playback = try #require(built.playback as? SkinnedPosePlayback)
        #expect(built.object.pose === playback.pose)
        #expect(built.object.reference == 0x500)
        #expect(playback.skeleton.boneNames == BehaviorProjectFixture.rig.boneNames)
    }

    @Test func aPosedCopyReadsItsOwnBuffer() throws {
        let copy = PosedCopy(instance: Self.instance(), skeleton: BehaviorProjectFixture.rig)
        let playback = try #require(copy.playback as? SkinnedPosePlayback)
        #expect(copy.pose === playback.pose)
        #expect(copy.instance.formID == 0x500)
    }
}
