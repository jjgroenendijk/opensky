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
        let first = EffectModelPoser.Copy(
            model: RenderModel(meshes: [], renderMaterials: []), skeleton: skeleton
        )
        let second = EffectModelPoser.Copy(
            model: RenderModel(meshes: [], renderMaterials: []), skeleton: skeleton
        )
        #expect(first.playback.skeleton.boneNames == ["FXRoot"])
        #expect(first.pose !== second.pose)
    }
}
