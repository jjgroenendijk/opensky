// The first-person rig finds its camera bone by name, and a rig without one keeps none.

import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
struct PlayerFirstPersonRigTests {
    private static func skeleton(_ bones: [String]) -> HKASkeleton {
        HKASkeleton(
            name: nil,
            bones: bones.map { HKABone(name: $0, lockTranslation: false) },
            parentIndices: bones.indices.map { $0 - 1 },
            referencePose: bones.map { _ in HKABonePose(transform: matrix_identity_float4x4) }
        )
    }

    private static func assembly() -> ActorAssembly<ActorRenderAsset> {
        let base = FormID(0x7)
        let visual = ResolvedActorVisual(
            appearance: ResolvedActorAppearance(
                base: base, chain: [.npc(base)],
                isFemale: ActorSourcedField(value: false, source: base),
                race: ActorSourcedField(value: nil, source: base),
                voiceType: ActorSourcedField(value: nil, source: base),
                wornArmor: ActorSourcedField(value: nil, source: base),
                headParts: ActorSourcedField(value: [], source: base),
                hairColor: ActorSourcedField(value: nil, source: base),
                defaultOutfit: ActorSourcedField(value: nil, source: base)
            ),
            skeletonPath: nil, skin: base, equippedSlots: [], parts: [], attachments: [],
            usesRuntimeEquipment: false, faceGenMeshPath: nil, faceGenTintPath: nil, skips: []
        )
        return ActorAssembly(
            actor: base, visual: visual, transform: matrix_identity_float4x4, models: [],
            skips: []
        )
    }

    private static func rig(bones: [String]) -> PlayerFirstPersonRig {
        PlayerFirstPersonRig(
            assembly: assembly(),
            animation: SkinnedPosePlayback(skeleton: skeleton(bones), models: [])
        )
    }

    @Test func theRigFindsItsCameraBone() {
        let rig = Self.rig(bones: ["NPC Root [Root]", FirstPersonCamera.cameraBoneName])
        #expect(rig.cameraBoneIndex == 1)
        #expect(rig.render.opaque.isEmpty)
    }

    @Test func aRigWithoutACameraBoneKeepsNone() {
        #expect(Self.rig(bones: ["NPC Root [Root]"]).cameraBoneIndex == nil)
    }

    @Test func aBuiltRigPosesBothViewsThroughTheGivenBuffers() {
        let rig = PlayerRenderRig(assembly: Self.assembly())
        let bodyPose = SkinnedPoseBuffer()
        let armsPose = SkinnedPoseBuffer()
        let body = PlayerBody(
            rig: rig, skeleton: Self.skeleton(["NPC Root [Root]"]), pose: bodyPose
        )
        let arms = PlayerFirstPersonRig(
            rig: rig, skeleton: Self.skeleton([FirstPersonCamera.cameraBoneName]), pose: armsPose
        )
        #expect(body.animation.pose === bodyPose)
        #expect(arms.animation.pose === armsPose)
        #expect(arms.cameraBoneIndex == 0)
    }
}
