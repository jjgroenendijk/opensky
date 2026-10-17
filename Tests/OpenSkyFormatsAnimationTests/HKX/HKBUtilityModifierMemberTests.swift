// Member-value tests for the Bethesda utility modifiers, the foot IK solver, and
// the vector transform. Offsets are in docs/formats/hkx-behavior-modifiers.md.
// All values are invented.

import Foundation
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct HKBUtilityModifierMemberTests {
    @Test func timerReadsAlarmMembers() throws {
        let node = try decodeHKBObject(BSTimerModifier.className, BSTimerModifier.decode) {
            $0.setFloat(2.5, at: 0x50)
            $0.setInt32(7, at: 0x58)
            $0.setBool(true, at: 0x68)
        }
        #expect(node.alarmTimeSeconds == 2.5)
        #expect(node.alarmEvent.id == 7)
        #expect(node.resetAlarm)
    }

    @Test func decomposeAndTimeStepReadTheirValues() throws {
        let decompose = try decodeHKBObject(
            BSDecomposeVectorModifier.className, BSDecomposeVectorModifier.decode
        ) {
            $0.setVector4(SIMD4(1, 2, 3, 4), at: 0x50)
            $0.setFloat(5, at: 0x60)
            $0.setFloat(6, at: 0x64)
            $0.setFloat(7, at: 0x68)
            $0.setFloat(8, at: 0x6C)
        }
        #expect(decompose.vector == SIMD4(1, 2, 3, 4))
        #expect(decompose.components == SIMD4(5, 6, 7, 8))

        let step = try decodeHKBObject(
            BSGetTimeStepModifier.className, BSGetTimeStepModifier.decode
        ) { $0.setFloat(0.016, at: 0x50) }
        #expect(step.timeStep == 0.016)
    }

    @Test func iStateManagerReadsItsStateData() throws {
        let node = try decodeHKBObject(
            BSIStateManagerModifier.className, BSIStateManagerModifier.decode
        ) {
            $0.setInt32(3, at: 0x50)
            $0.setArray(at: 0x58, count: 2, dataOffset: 0x200)
            $0.setInt32(10, at: 0x208)
            $0.setInt32(11, at: 0x20C)
            $0.setInt32(20, at: 0x218)
            $0.setInt32(21, at: 0x21C)
        }
        #expect(node.iStateVar == 3)
        #expect(node.stateData.map(\.stateID) == [10, 20])
        #expect(node.stateData.map(\.stateToSetAs) == [11, 21])
    }

    @Test func tweenerAndPassByReadTheirTargets() throws {
        let tweener = try decodeHKBObject(BSTweenerModifier.className, BSTweenerModifier.decode) {
            $0.setBool(true, at: 0x50)
            $0.setBool(true, at: 0x52)
            $0.setFloat(0.75, at: 0x54)
            $0.setVector4(SIMD4(1, 2, 3, 0), at: 0x60)
            $0.setVector4(SIMD4(0, 0, 0, 1), at: 0x70)
        }
        #expect(tweener.tweenPosition && !tweener.tweenRotation && tweener.useTweenDuration)
        #expect(tweener.tweenDuration == 0.75)
        #expect(tweener.targetPosition == SIMD4(1, 2, 3, 0))
        #expect(tweener.targetRotation == SIMD4(0, 0, 0, 1))

        let passBy = try decodeHKBObject(
            BSPassByTargetTriggerModifier.className, BSPassByTargetTriggerModifier.decode
        ) {
            $0.setVector4(SIMD4(4, 5, 6, 0), at: 0x50)
            $0.setFloat(30, at: 0x60)
            $0.setVector4(SIMD4(0, 1, 0, 0), at: 0x70)
            $0.setInt32(9, at: 0x80)
        }
        #expect(passBy.targetPosition == SIMD4(4, 5, 6, 0))
        #expect(passBy.radius == 30)
        #expect(passBy.movementDirection == SIMD4(0, 1, 0, 0))
        #expect(passBy.triggerEvent.id == 9)
    }

    @Test func limbIkReadsItsChain() throws {
        let node = try decodeHKBObject(BSLimbIKModifier.className, BSLimbIKModifier.decode) {
            $0.setFloat(45, at: 0x50)
            $0.setInt16(2, at: 0x58)
            $0.setInt16(4, at: 0x5A)
            $0.setFloat(0.5, at: 0x5C)
            $0.setFloat(3, at: 0x60)
            $0.setFloat(1.5, at: 0x64)
        }
        #expect(node.limitAngleDegrees == 45)
        #expect([node.startBoneIndex, node.endBoneIndex] == [2, 4] as [Int])
        #expect([node.gain, node.boneRadius, node.castOffset] == [0.5, 3, 1.5])
    }

    @Test func footIkReadsGainsLegsAndGround() throws {
        let node = try decodeHKBObject(HKBFootIkModifier.className, HKBFootIkModifier.decode) {
            $0.setFloat(0.2, at: 0x50)
            $0.setArray(at: 0x80, count: 1, dataOffset: 0x200)
            $0.setVector4(SIMD4(0, 0, 1, 0), at: 0x240)
            $0.setVector4(SIMD4(0, 4, 0, 0), at: 0x250)
            $0.setInt32(5, at: 0x260)
            $0.setFloat(2, at: 0x270)
            $0.setFloat(7, at: 0x274)
            $0.setFloat(12, at: 0x278)
            $0.setFloat(-3, at: 0x27C)
            $0.setFloat(170, at: 0x280)
            $0.setFloat(10, at: 0x284)
            $0.setFloat(80, at: 0x28C)
            $0.setInt16(1, at: 0x290)
            $0.setInt16(2, at: 0x292)
            $0.setInt16(3, at: 0x294)
            $0.setFloat(50, at: 0x90)
            $0.setFloat(60, at: 0x94)
            $0.setFloat(1.25, at: 0x98)
            $0.setFloat(-0.5, at: 0xC0)
            $0.setBool(true, at: 0xD5)
            $0.setUInt8(1, at: 0xD7)
        }
        #expect(node.gains.value("onOffGain") == 0.2)
        let leg = try #require(node.legs.first)
        #expect(leg.kneeAxisLS == SIMD4(0, 0, 1, 0))
        #expect(leg.footEndLS == SIMD4(0, 4, 0, 0))
        #expect(leg.ungroundedEvent.id == 5)
        #expect([leg.footPlantedAnkleHeightMS, leg.footRaisedAnkleHeightMS] == [2, 7])
        #expect([leg.maxAnkleHeightMS, leg.minAnkleHeightMS] == [12, -3])
        #expect([leg.maxKneeAngleDegrees, leg.minKneeAngleDegrees] == [170, 10])
        #expect(leg.maxAnkleAngleDegrees == 80)
        #expect([leg.hipIndex, leg.kneeIndex, leg.ankleIndex] == [1, 2, 3] as [Int])
        #expect([node.raycastDistanceUp, node.raycastDistanceDown] == [50, 60])
        #expect([node.originalGroundHeightMS, node.verticalOffset] == [1.25, -0.5])
        #expect(node.lockFeetWhenPlanted && !node.useTrackData)
        #expect(node.alignMode == 1)
    }

    @Test func transformVectorReadsItsFlags() throws {
        let node = try decodeHKBObject(
            HKBTransformVectorModifier.className, HKBTransformVectorModifier.decode
        ) {
            $0.setVector4(SIMD4(0, 0, 0, 1), at: 0x50)
            $0.setVector4(SIMD4(1, 2, 3, 0), at: 0x60)
            $0.setVector4(SIMD4(4, 5, 6, 0), at: 0x70)
            $0.setVector4(SIMD4(7, 8, 9, 0), at: 0x80)
            $0.setBool(true, at: 0x90)
            $0.setBool(true, at: 0x93)
        }
        #expect(node.rotation == SIMD4(0, 0, 0, 1))
        #expect(node.translation == SIMD4(1, 2, 3, 0))
        #expect(node.vectorIn == SIMD4(4, 5, 6, 0))
        #expect(node.vectorOut == SIMD4(7, 8, 9, 0))
        #expect(node.rotateOnly && !node.inverse && !node.computeOnActivate)
        #expect(node.computeOnModify)
    }
}
