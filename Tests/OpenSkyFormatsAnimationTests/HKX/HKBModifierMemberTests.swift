// Member-value tests for the behavior modifiers. Each test writes distinct
// values at the offsets in docs/formats/hkx-behavior-modifiers.md and reads
// every member back. All values are invented.

import Foundation
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

/// Decodes one object of `className` at offset 0 after `writes` fill it.
/// Array element data and strings go at 0x200 and above.
func decodeHKBObject<Decoded>(
    _ className: String,
    _ decoder: (HKXPointerTarget, HKXObjectGraph) -> Decoded?,
    writes: (inout HKBNodeFixture) -> Void
) throws -> Decoded {
    var fixture = HKBNodeFixture(payloadSize: 0x400)
    let target = fixture.addObject(className, at: 0)
    writes(&fixture)
    return try #require(decoder(target, fixture.buildGraph()))
}

@Suite(.tags(.parser))
struct HKBModifierMemberTests {
    @Test func directAtReadsEveryDocumentedMember() throws {
        let node = try decodeHKBObject(BSDirectAtModifier.className, BSDirectAtModifier.decode) {
            $0.setBool(true, at: 0x50)
            $0.setInt16(4, at: 0x52)
            $0.setFloat(11, at: 0x60)
            $0.setFloat(12, at: 0x64)
            $0.setFloat(0.25, at: 0x68)
            $0.setFloat(0.5, at: 0x6C)
            $0.setVector4(SIMD4(1, 2, 3, 0), at: 0x70)
            $0.setUInt32(0xABCD, at: 0x80)
            $0.setFloat(7, at: 0x88)
            $0.setFloat(8, at: 0x8C)
            $0.setFloat(9, at: 0x90)
            $0.setBool(true, at: 0x94)
            $0.setFloat(21, at: 0x98)
            $0.setFloat(22, at: 0x9C)
        }
        #expect(node.directAtTarget && node.active)
        #expect(node.sourceBoneIndex == 4)
        #expect([node.offsetHeadingDegrees, node.offsetPitchDegrees] == [11, 12])
        #expect([node.onGain, node.offGain] == [0.25, 0.5])
        #expect(node.targetLocation == SIMD4(1, 2, 3, 0))
        #expect(node.userInfo == 0xABCD)
        #expect([node.directAtCameraX, node.directAtCameraY, node.directAtCameraZ] == [7, 8, 9])
        #expect([node.currentHeadingOffset, node.currentPitchOffset] == [21, 22])
    }

    @Test func lookAtReadsEveryDocumentedMember() throws {
        let node = try decodeHKBObject(BSLookAtModifier.className, BSLookAtModifier.decode) {
            $0.setBool(true, at: 0x50)
            $0.setArray(at: 0x58, count: 1, dataOffset: 0x200)
            $0.setInt16(6, at: 0x200)
            $0.setVector4(SIMD4(0, 1, 0, 0), at: 0x210)
            $0.setFloat(45, at: 0x220)
            $0.setFloat(0.1, at: 0x224)
            $0.setFloat(0.2, at: 0x228)
            $0.setBool(true, at: 0x22C)
            $0.setFloat(30, at: 0x7C)
            $0.setBool(true, at: 0x80)
            $0.setFloat(0.3, at: 0x84)
            $0.setFloat(0.4, at: 0x88)
            $0.setBool(true, at: 0x8C)
            $0.setVector4(SIMD4(4, 5, 6, 0), at: 0x90)
            $0.setBool(true, at: 0xA0)
            $0.setBool(true, at: 0xB8)
            $0.setFloat(1, at: 0xBC)
            $0.setFloat(2, at: 0xC0)
            $0.setFloat(3, at: 0xC4)
        }
        #expect(node.lookAtTarget && node.continueLookOutsideOfLimit)
        #expect(node.useBoneGains && node.targetOutsideLimits && node.lookAtCamera)
        #expect(node.limitAngleThresholdDegrees == 30)
        #expect([node.onGain, node.offGain] == [0.3, 0.4])
        #expect(node.targetLocation == SIMD4(4, 5, 6, 0))
        #expect([node.lookAtCameraX, node.lookAtCameraY, node.lookAtCameraZ] == [1, 2, 3])
        let bone = try #require(node.bones.first)
        #expect(bone.index == 6)
        #expect(bone.forwardAxisLS == SIMD4(0, 1, 0, 0))
        #expect([bone.limitAngleDegrees, bone.onGain, bone.offGain] == [45, 0.1, 0.2])
        #expect(bone.enabled)
    }

    @Test func bethesdaModifiersReadTheirDocumentedMembers() throws {
        let isActive = try decodeHKBObject(
            BSIsActiveModifier.className,
            BSIsActiveModifier.decode
        ) {
            $0.setBool(true, at: 0x53)
        }
        #expect(isActive.invertActive == [false, true, false, false, false])

        let everyN = try decodeHKBObject(
            BSEventEveryNEventsModifier.className, BSEventEveryNEventsModifier.decode
        ) { $0.setUInt8(3, at: 0x71) }
        #expect(everyN.minimumNumberOfEventsBeforeSend == 3)

        let falseToTrue = try decodeHKBObject(
            BSEventOnFalseToTrueModifier.className, BSEventOnFalseToTrueModifier.decode
        ) { $0.setBool(true, at: 0x50 + 0x18 + 1) }
        #expect(falseToTrue.slots.map(\.variableToTest) == [false, true, false])

        let interp = try decodeHKBObject(
            BSInterpValueModifier.className,
            BSInterpValueModifier.decode
        ) {
            $0.setFloat(0.75, at: 0x58)
        }
        #expect(interp.result == 0.75)

        let sampler = try decodeHKBObject(
            BSSpeedSamplerModifier.className, BSSpeedSamplerModifier.decode
        ) {
            $0.setFloat(90, at: 0x54)
            $0.setFloat(120, at: 0x5C)
        }
        #expect([sampler.direction, sampler.speedOut] == [90, 120])
    }

    @Test func boneModifiersReadTheirDocumentedMembers() throws {
        let twist = try decodeHKBObject(HKBTwistModifier.className, HKBTwistModifier.decode) {
            $0.setVector4(SIMD4(0, 0, 1, 0), at: 0x50)
            $0.setUInt8(1, at: 0x68)
            $0.setUInt8(2, at: 0x69)
            $0.setBool(true, at: 0x6A)
        }
        #expect(twist.axisOfRotation == SIMD4(0, 0, 1, 0))
        #expect([twist.setAngleMethod, twist.rotationAxisCoordinates] == [1, 2] as [Int])
        #expect(twist.isAdditive)

        let rotate = try decodeHKBObject(
            HKBRotateCharacterModifier.className, HKBRotateCharacterModifier.decode
        ) { $0.setVector4(SIMD4(1, 0, 0, 0), at: 0x60) }
        #expect(rotate.axisOfRotation == SIMD4(1, 0, 0, 0))

        let getUp = try decodeHKBObject(HKBGetUpModifier.className, HKBGetUpModifier.decode) {
            $0.setVector4(SIMD4(0, 0, 1, 0), at: 0x50)
            $0.setInt16(1, at: 0x68)
            $0.setInt16(2, at: 0x6A)
            $0.setInt16(3, at: 0x6C)
        }
        #expect(getUp.groundNormal == SIMD4(0, 0, 1, 0))
        #expect([getUp.rootBoneIndex, getUp.otherBoneIndex, getUp.anotherBoneIndex] ==
            [1, 2, 3] as [Int])
    }

    @Test func keyframeInfoReadsEveryElementMember() throws {
        let node = try decodeHKBObject(
            HKBKeyframeBonesModifier.className, HKBKeyframeBonesModifier.decode
        ) {
            $0.setArray(at: 0x50, count: 1, dataOffset: 0x200)
            $0.setVector4(SIMD4(1, 2, 3, 1), at: 0x200)
            $0.setVector4(SIMD4(0, 0, 0, 1), at: 0x210)
            $0.setInt16(9, at: 0x220)
            $0.setBool(true, at: 0x222)
        }
        let info = try #require(node.keyframeInfo.first)
        #expect(info.keyframedPosition == SIMD4(1, 2, 3, 1))
        #expect(info.keyframedRotation == SIMD4(0, 0, 0, 1))
        #expect(info.boneIndex == 9)
        #expect(info.isValid)
    }

    @Test func dampingReadsItsStateMembers() throws {
        let node = try decodeHKBObject(HKBDampingModifier.className, HKBDampingModifier.decode) {
            $0.setFloat(1, at: 0x60)
            $0.setFloat(2, at: 0x64)
            $0.setVector4(SIMD4(repeating: 3), at: 0x70)
            $0.setVector4(SIMD4(repeating: 4), at: 0x80)
            $0.setVector4(SIMD4(repeating: 5), at: 0x90)
            $0.setVector4(SIMD4(repeating: 6), at: 0xA0)
            $0.setFloat(7, at: 0xB0)
            $0.setFloat(8, at: 0xB4)
        }
        #expect([node.rawValue, node.dampedValue, node.errorSum, node.previousError] == [
            1,
            2,
            7,
            8
        ])
        #expect(node.rawVector == SIMD4(repeating: 3))
        #expect(node.dampedVector == SIMD4(repeating: 4))
        #expect(node.vectorErrorSum == SIMD4(repeating: 5))
        #expect(node.vectorPreviousError == SIMD4(repeating: 6))
    }

    @Test func footIkReadsLegsAndGroundAlignment() throws {
        let node = try decodeHKBObject(
            HKBFootIkControlsModifier.className, HKBFootIkControlsModifier.decode
        ) {
            $0.setArray(at: 0x80, count: 1, dataOffset: 0x200)
            $0.setVector4(SIMD4(1, 2, 0, 0), at: 0x200)
            $0.setFloat(0.5, at: 0x220)
            $0.setBool(true, at: 0x224)
            $0.setBool(true, at: 0x225)
            $0.setVector4(SIMD4(0, 0, 3, 0), at: 0x90)
            $0.setVector4(SIMD4(0, 0, 0, 1), at: 0xA0)
        }
        let leg = try #require(node.legs.first)
        #expect(leg.groundPosition == SIMD4(1, 2, 0, 0))
        #expect(leg.verticalError == 0.5)
        #expect(leg.hitSomething && leg.isPlantedMS)
        #expect(node.errorOutTranslation == SIMD4(0, 0, 3, 0))
        #expect(node.alignWithGroundRotation == SIMD4(0, 0, 0, 1))
    }

    @Test func poweredRagdollReadsControlAndModeData() throws {
        let node = try decodeHKBObject(
            HKBPoweredRagdollControlsModifier.className, HKBPoweredRagdollControlsModifier.decode
        ) {
            $0.setFloat(4, at: 0x5C)
            $0.setFloat(5, at: 0x60)
            $0.setInt16(1, at: 0x78)
            $0.setInt16(2, at: 0x7A)
            $0.setInt16(3, at: 0x7C)
            $0.setUInt8(2, at: 0x7E)
        }
        #expect([node.proportionalRecoveryVelocity, node.constantRecoveryVelocity] == [4, 5])
        #expect([node.poseMatchingBone0, node.poseMatchingBone1, node.poseMatchingBone2] == [
            1,
            2,
            3
        ] as [Int])
        #expect(node.worldFromModelMode == 2)
    }
}
