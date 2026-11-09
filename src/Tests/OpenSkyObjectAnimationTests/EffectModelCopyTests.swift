// A posed copy of an effect model poses its own buffer over the effect's rig.

import OpenSkyBehavior
import OpenSkyFormatsAnimation
@testable import OpenSkyObjectAnimation
import OpenSkyPlayer
@testable import OpenSkyRendering
import simd
import Testing

@MainActor
struct EffectModelCopyTests {
    @Test func aCopyPosesItsOwnBufferOverTheRig() {
        let skeleton = HKASkeleton(
            name: nil,
            bones: [HKABone(name: "FXRoot", lockTranslation: false)],
            parentIndices: [-1],
            referencePose: [HKABonePose(transform: matrix_identity_float4x4)]
        )
        let make: EffectModelPoser.MakePlayback = {
            SkinnedPosePlayback(skeleton: $0, pose: $1, models: [$2])
        }
        let first = EffectModelPoser.Copy(
            model: RenderModel(meshes: [], renderMaterials: []), skeleton: skeleton,
            makePlayback: make
        )
        let second = EffectModelPoser.Copy(
            model: RenderModel(meshes: [], renderMaterials: []), skeleton: skeleton,
            makePlayback: make
        )
        let playback = first.playback as? SkinnedPosePlayback
        #expect(playback?.skeleton.boneNames == ["FXRoot"])
        #expect(playback?.pose === first.pose)
        #expect(first.pose !== second.pose)
    }
}
