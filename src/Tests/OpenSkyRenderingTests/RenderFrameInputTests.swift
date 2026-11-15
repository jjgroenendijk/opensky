// The per-frame input's pose maps take a new revision on each change, so the
// renderer merges them only on a frame that changed them.

@testable import OpenSkyRendering
import simd
import Testing

struct RenderFrameInputTests {
    @Test
    @MainActor
    func eachPoseChangeTakesANewRevision() {
        var poses = RenderInstancePoses()
        let start = poses.revision
        poses.dynamicDeltas[1] = matrix_identity_float4x4
        let afterDynamic = poses.revision
        poses.npcDeltas[2] = matrix_identity_float4x4
        poses.vehiclePoses[3] = matrix_identity_float4x4
        poses.scriptedPoses[4] = matrix_identity_float4x4
        #expect(afterDynamic != start)
        #expect(poses.revision != afterDynamic)
    }

    @Test
    @MainActor
    func aCopyKeepsItsRevisionUntilItChanges() {
        var poses = RenderInstancePoses()
        poses.dynamicDeltas[1] = matrix_identity_float4x4
        var copy = poses
        #expect(copy.revision == poses.revision)
        copy.dynamicDeltas[1] = nil
        #expect(copy.revision != poses.revision)
    }

    @Test
    @MainActor
    func revisionsFromTwoValuesNeverMatchAfterAChange() {
        var first = RenderInstancePoses()
        var second = RenderInstancePoses()
        first.dynamicDeltas[1] = matrix_identity_float4x4
        second.dynamicDeltas[1] = matrix_identity_float4x4
        #expect(first.revision != second.revision)
    }

    @Test
    func aWiderHorizontalViewWidensTheVerticalOneAtTheAspect() {
        let square = RenderFrameInput.widened(fovY: .pi / 2, byHorizontal: .pi / 18, aspect: 1)
        #expect(abs(square - (.pi / 2 + .pi / 18)) < 0.0001, "at aspect 1 both grow alike")
        let wide = RenderFrameInput.widened(fovY: 1, byHorizontal: 0.2, aspect: 16 / 9)
        #expect(wide > 1 && wide < 1.2, "a wide drawable gains less vertical view")
        #expect(RenderFrameInput.widened(fovY: 1, byHorizontal: 0, aspect: 2) == 1)
    }
}
