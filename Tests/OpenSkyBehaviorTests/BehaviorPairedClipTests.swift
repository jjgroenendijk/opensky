// A paired clip poses two actors: each one plays only its own tracks, found by bone name,
// and hears only its own tracks' annotations.

@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
import Testing

struct BehaviorPairedClipTests {
    private struct NamedClip: BehaviorClip {
        let duration: Float = 1
        let trackNames: [String?]
        let trackAnnotations: [Int: [HKAAnnotation]]

        func samples(at _: Float) -> [HKABoneTransformSample] {
            trackNames.indices.map {
                HKABoneTransformSample(boneIndex: $0, pose: HKABonePose(
                    translation: .zero, rotation: BehaviorPoseMath.identityRotation,
                    scale: SIMD3(1, 1, 1)
                ))
            }
        }

        func annotations(onTracks tracks: Set<Int>) -> [HKAAnnotation] {
            tracks.sorted().flatMap { trackAnnotations[$0] ?? [] }
        }
    }

    private static let tracks: [String?] = ["PairedRoot", "2_HorsePelvis", "NPC Root [Root]", nil]

    @Test func theLeadActorTakesThePlainTracks() {
        let map = PairedTrackMap(
            trackNames: Self.tracks, prefix: "", boneNames: ["NPC Root [Root]", "NPC Pelvis"]
        )
        #expect(map.bones == [2: 0])
    }

    @Test func theOtherActorTakesItsPrefixedTracks() {
        let map = PairedTrackMap(
            trackNames: Self.tracks, prefix: "2_", boneNames: ["HorseRoot", "HorsePelvis"]
        )
        #expect(map.bones == [1: 1])
        #expect(PairedTrackMap.boneName(of: "12_Bone", prefix: "") == nil)
        #expect(PairedTrackMap.boneName(of: "Bone_2", prefix: "") == "Bone_2")
    }

    @Test func theViewRemapsSamplesAndKeepsItsOwnAnnotations() {
        let sound = HKAAnnotation(time: 0, text: "SoundPlay.NPCHorseMount")
        let clip = NamedClip(
            trackNames: Self.tracks, trackAnnotations: [2: [sound], 1: [HKAAnnotation(
                time: 0.5, text: "HorseOnly"
            )]]
        )
        let rider = PairedBehaviorClip(clip, map: PairedTrackMap(
            trackNames: Self.tracks, prefix: "", boneNames: ["NPC Root [Root]"]
        ))
        #expect(rider.samples(at: 0).map(\.boneIndex) == [0])
        #expect(rider.annotations == [sound])
    }
}
