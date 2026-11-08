// A ragdoll override names only its own bones; every bone below one moves with it.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct SkeletonPoseOverridingTests {
    private static func pose(_ names: [String], at heights: [Float]) -> SkeletonPose {
        SkeletonPose(
            bones: SkeletonBoneIndex(names: names),
            matrices: heights.map { MatrixMath.translation(SIMD3(0, 0, $0)) }
        )
    }

    @Test
    func aBoneBelowAReplacedOneMovesWithIt() {
        let pose = Self.pose(["Root", "Arm", "Hand", "Finger"], at: [0, 100, 90, 85])
        let fallen = MatrixMath.translation(SIMD3(50, 0, 10))

        let posed = pose.overriding(["Arm": fallen], parents: [-1, 0, 1, 2]).named

        #expect(posed["Root"]?.columns.3 == SIMD4(0, 0, 0, 1), "a bone above stays")
        #expect(posed["Arm"]?.columns.3 == SIMD4(50, 0, 10, 1))
        #expect(posed["Hand"]?.columns.3 == SIMD4(50, 0, 0, 1), "keeps its offset to the arm")
        #expect(posed["Finger"]?.columns.3 == SIMD4(50, 0, -5, 1))
    }

    @Test
    func aChildListedBeforeItsParentStillFollows() {
        let pose = Self.pose(["Finger", "Hand", "Root"], at: [85, 90, 0])
        let lifted = MatrixMath.translation(SIMD3(0, 0, 190))

        let posed = pose.overriding(["Hand": lifted], parents: [1, 2, -1]).named

        #expect(posed["Finger"]?.columns.3 == SIMD4(0, 0, 185, 1))
        #expect(posed["Root"]?.columns.3 == SIMD4(0, 0, 0, 1))
    }

    @Test
    func aChildOfTwoReplacedBonesTakesItsOwnReplacement() {
        let pose = Self.pose(["Root", "Hand", "Finger"], at: [0, 90, 85])
        let posed = pose.overriding(
            [
                "Hand": MatrixMath.translation(SIMD3(10, 0, 0)),
                "Finger": MatrixMath.translation(SIMD3(20, 0, 0))
            ],
            parents: [-1, 0, 1]
        ).named

        #expect(posed["Finger"]?.columns.3 == SIMD4(20, 0, 0, 1))
    }
}
