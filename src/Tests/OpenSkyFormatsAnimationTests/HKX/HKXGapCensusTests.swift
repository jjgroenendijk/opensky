// HKXGapCensus: Havok classes by objects, and how annotation events are folded, over
// synthetic packfiles (HKXFixture).

import Foundation
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct HKXGapCensusTests {
    @Test func countsObjectsByClass() {
        var fixture = HKXFixture()
        fixture.virtualFixups = [.init(
            dataOffset: 24, classNameSection: 0,
            classNameOffset: UInt32(fixture.nameOffset(ofClass: 0))
        )]
        var census = HKXGapCensus()
        census.record(data: fixture.build())

        #expect(census.fileCount == 1)
        #expect(census.classes.uses == ["hkRootLevelContainer": 1, "hkClass": 1])
        #expect(census.classes.left(where: HKXGapCensus.decoded.contains).map(\.name)
            == ["hkClass"])
    }

    @Test func everyClassTheInstallUsesHasADecoder() {
        let skeletonAndPhysics: Set = [
            "hkMemoryResourceContainer", "hkMemoryResourceHandle", "hkpConstraintInstance",
            "hkpRigidBody", "hkpRagdollConstraintData", "hkpShapeInfo", "hkpCapsuleShape",
            "hkpLimitedHingeConstraintData", "hkpConvexTranslateShape", "hkpBoxShape",
            "hkaSkeletonMapper", "hkaRagdollInstance", "hkpPhysicsData", "hkpPhysicsSystem",
            "hkpPositionConstraintMotor", "hkpConvexTransformShape",
            "hkpConvexVerticesConnectivity", "hkpConvexVerticesShape", "hkpListShape",
            "hkpMoppBvTreeShape", "hkpMoppCode"
        ]
        let behaviorAndAnimation: Set = [
            "BGSGamebryoSequenceGenerator", "hkbProjectStringData", "hkbCharacterStringData",
            "hkbMirroredSkeletonInfo", "hkbFootIkDriverInfo", "hkaAnnotationTrack",
            "hkaDefaultAnimatedReferenceFrame", "hkaInterleavedUncompressedAnimation"
        ]
        let missing = skeletonAndPhysics.union(behaviorAndAnimation)
            .subtracting(HKXGapCensus.decoded)
        #expect(missing.isEmpty, "\(missing.sorted())")
    }

    @Test func aFileThatDoesNotDecodeIsOneFailure() {
        var census = HKXGapCensus()
        census.record(data: Data("not havok".utf8))
        #expect(census.failures.total == 1)
        #expect(census.classes.total == 0)
    }

    @Test func annotationPayloadsFoldIntoTheirEvent() {
        #expect(HKXGapCensus.event("SoundPlay.NPCFootstep") == "SoundPlay.*")
        #expect(HKXGapCensus.event("PIE@SGVF|x") == "PIE.*")
        #expect(HKXGapCensus.event("HitFrame") == "HitFrame")
    }

    @Test func expressionAssignmentsNameTheirVariable() {
        #expect(HKXGapCensus
            .assignedVariable("turnSpeedMult = fabs(TurnDelta/90)") == "turnSpeedMult")
        #expect(HKXGapCensus.assignedVariable("weaponDraw if (iCombatStance == 1)") == nil)
        #expect(HKXGapCensus.assignedVariable("x if (a >= 1)") == nil)
    }

    /// The census keeps the names a graph declares, so `fabs` and `90` drop out.
    @Test func expressionsNameTheVariablesTheyRead() {
        #expect(HKXGapCensus.identifiers(in: "turnLeft if (TurnDelta > TurnMin)")
            == ["turnLeft", "if", "TurnDelta", "TurnMin"])
        #expect(HKXGapCensus.identifiers(in: "1stPRot = sind(Direction * 360)")
            == ["1stPRot", "sind", "Direction", "360"])
    }
}
