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
}
