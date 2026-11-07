// A behaviour graph's sequence generator plays a mesh's controller sequence: the rig of
// a graph mesh poses the nodes its sequences move. Synthetic nodes only.

import OpenSkyFormatsMesh
@testable import OpenSkyObjectAnimation
import simd
import Testing

struct GraphSequencePlaybackTests {
    private static let animation = NIFNodeAnimation(
        nodes: [
            .init(name: "Root", parent: nil, rest: .identity),
            .init(name: "FanBlade", parent: 0, rest: .identity)
        ],
        controllers: []
    )

    private static let spin = NIFSequence(
        name: "AnimIdle",
        timing: ControllerTiming(cycle: .loop, frequency: 1, phase: 0, startTime: 0, stopTime: 2),
        textKeys: [],
        tracks: [NIFSequenceTrack(
            target: .node("fanblade"),
            channel: .transform(NIFTransformChannel(
                translation: SIMD3(0, 0, 7), rotation: nil, scale: nil, keys: nil
            ))
        )]
    )

    @Test func aGraphMeshRigPosesTheNodesItsSequencesMove() throws {
        let rig = try #require(
            NodeControllerRig(animation: Self.animation, lagOnly: true, sequences: [Self.spin])
        )
        #expect(rig.boneNodes == [1])
        #expect(rig.sequence(named: "animidle") != nil)
        #expect(NodeControllerRig(animation: Self.animation, lagOnly: true) == nil)
    }

    @Test func playingASequenceSetsItsNodesByName() {
        var animator = NIFNodeAnimator(animation: Self.animation)
        animator.play(Self.spin, after: 3)
        #expect(animator.locals[1].translation == SIMD3(0, 0, 7))
        #expect(animator.locals[0] == .identity)
    }
}
