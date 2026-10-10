// Member-value tests for generators, conditions, the state machine, and the
// graph data. Offsets come from docs/formats/hkx-behavior-nodes.md,
// hkx-behavior-modifiers.md, and hkx-behavior.md. All values are invented.

import Foundation
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct HKBGeneratorMemberTests {
    @Test func bethesdaGeneratorsReadTheirDocumentedMembers() throws {
        let sync = try decodeHKBObject(
            BSSynchronizedClipGenerator.className, BSSynchronizedClipGenerator.decode
        ) {
            $0.setBool(true, at: 0x60)
            $0.setFloat(0.5, at: 0x64)
            $0.setFloat(0.1, at: 0x68)
            $0.setBool(true, at: 0x6D)
            $0.setBool(true, at: 0x6E)
        }
        #expect(sync.syncClipIgnoreMarkPlacement)
        #expect([sync.getToMarkTime, sync.markErrorThreshold] == [0.5, 0.1])
        #expect(sync.reorientSupportChar && sync.applyMotionFromRoot)

        let cyclic = try decodeHKBObject(
            BSCyclicBlendTransitionGenerator.className, BSCyclicBlendTransitionGenerator.decode
        ) {
            $0.setFloat(0.6, at: 0x78)
            $0.setUInt8(2, at: 0x80)
        }
        #expect(cyclic.blendParameter == 0.6)
        #expect(cyclic.blendCurve == 2)

        let offset = try decodeHKBObject(
            BSOffsetAnimationGenerator.className, BSOffsetAnimationGenerator.decode
        ) { $0.setFloat(0.3, at: 0x68) }
        #expect(offset.offsetVariable == 0.3)
    }

    @Test func poseMatchingReadsBlenderAndOwnMembers() throws {
        let node = try decodeHKBObject(
            HKBPoseMatchingGenerator.className, HKBPoseMatchingGenerator.decode
        ) {
            $0.setFloat(-1, at: 0x50)
            $0.setFloat(1, at: 0x54)
            $0.setVector4(SIMD4(0, 0, 0, 1), at: 0xA0)
            $0.setFloat(2, at: 0xB0)
            $0.setFloat(3, at: 0xB4)
            $0.setFloat(4, at: 0xB8)
            $0.setFloat(5, at: 0xBC)
            $0.setInt32(6, at: 0xC0)
            $0.setInt32(7, at: 0xC4)
            $0.setInt16(8, at: 0xC8)
            $0.setInt16(9, at: 0xCA)
            $0.setInt16(10, at: 0xCC)
        }
        #expect(node.blender.minCyclicBlendParameter == -1)
        #expect(node.blender.maxCyclicBlendParameter == 1)
        #expect(node.worldFromModelRotation == SIMD4(0, 0, 0, 1))
        let times = [
            node.blendSpeed, node.minSpeedToSwitch,
            node.minSwitchTimeNoError, node.minSwitchTimeFullError
        ]
        #expect(times == [2, 3, 4, 5])
        #expect([node.startPlayingEventId, node.startMatchingEventId] == [6, 7] as [Int])
        #expect([node.rootBoneIndex, node.otherBoneIndex, node.anotherBoneIndex] ==
            [8, 9, 10] as [Int])
    }

    @Test func selectorsAndStateMachineReadTheirModeBytes() throws {
        let selector = try decodeHKBObject(
            HKBManualSelectorGenerator.className, HKBManualSelectorGenerator.decode
        ) { $0.setUInt8(2, at: 0x59) }
        #expect(selector.currentGeneratorIndex == 2)

        let effect = try decodeHKBObject(
            HKBBlendingTransitionEffect.className, HKBBlendingTransitionEffect.decode
        ) {
            $0.setUInt8(1, at: 0x48)
            $0.setUInt8(2, at: 0x49)
        }
        #expect([effect.selfTransitionMode, effect.eventMode] == [1, 2] as [Int])

        let machine = try decodeHKBObject(HKBStateMachine.className, HKBStateMachine.decode) {
            $0.setUInt8(3, at: 0x85)
            $0.setUInt8(1, at: 0x87)
        }
        #expect(machine.maxSimultaneousTransitions == 3)
        #expect(machine.selfTransitionMode == 1)
    }

    @Test func arrayElementsReadTheirDocumentedMembers() throws {
        let transitions = try decodeHKBObject(
            HKBStateMachineTransitionInfoArray.className, HKBStateMachineTransitionInfoArray.decode
        ) {
            $0.setArray(at: 0x10, count: 1, dataOffset: 0x200)
            $0.setInt32(12, at: 0x200 + 0x38)
        }
        #expect(transitions.transitions.map(\.fromNestedStateId) == [12])

        let triggers = try decodeHKBObject(
            HKBClipTriggerArray.className,
            HKBClipTriggerArray.decode
        ) {
            $0.setArray(at: 0x10, count: 1, dataOffset: 0x200)
            $0.setBool(true, at: 0x200 + 0x1A)
        }
        #expect(triggers.triggers.map(\.isAnnotation) == [true])

        let expressions = try decodeHKBObject(
            HKBExpressionDataArray.className, HKBExpressionDataArray.decode
        ) {
            $0.setArray(at: 0x10, count: 1, dataOffset: 0x200)
            $0.setString("speed > 1", at: 0x200, storage: 0x300)
            $0.setInt32(4, at: 0x208)
            $0.setInt32(5, at: 0x20C)
            $0.setUInt8(1, at: 0x210)
        }
        let expression = try #require(expressions.expressionsData.first)
        #expect(expression.expression == "speed > 1")
        #expect([expression.assignmentVariableIndex, expression.assignmentEventIndex] ==
            [4, 5] as [Int])
        #expect(expression.eventMode == 1)

        let ranges = try decodeHKBObject(
            HKBEventRangeDataArray.className, HKBEventRangeDataArray.decode
        ) {
            $0.setArray(at: 0x10, count: 1, dataOffset: 0x200)
            $0.setFloat(0.9, at: 0x200)
            $0.setUInt8(2, at: 0x218)
        }
        #expect(ranges.eventData.map(\.upperBound) == [0.9])
        #expect(ranges.eventData.map(\.eventMode) == [2])
    }

    @Test func graphDataReadsItsValueArrays() throws {
        let data = try decodeHKBObject(
            HKBBehaviorGraphData.className,
            HKBBehaviorGraphData.decode
        ) {
            $0.setArray(at: 0x10, count: 2, dataOffset: 0x200)
            $0.setFloat(0.5, at: 0x200)
            $0.setFloat(1.5, at: 0x204)
            $0.setArray(at: 0x30, count: 1, dataOffset: 0x220)
            $0.setUInt8(UInt8(HKBVariableType.real.rawValue), at: 0x224)
            $0.setArray(at: 0x50, count: 1, dataOffset: 0x240)
            $0.setInt32(-3, at: 0x240)
            $0.setArray(at: 0x60, count: 1, dataOffset: 0x260)
            $0.setInt32(3, at: 0x260)
        }
        #expect(data.attributeDefaults == [0.5, 1.5])
        #expect(data.characterPropertyInfos.map(\.type) == [.real])
        #expect(data.wordMinVariableValues == [-3])
        #expect(data.wordMaxVariableValues == [3])
    }

    @Test func characterDataReadsTheNamesFromItsStringData() throws {
        let data = try decodeHKBObject(HKBCharacterData.className, HKBCharacterData.decode) {
            $0.addObject("hkbCharacterStringData", at: 0x100)
            $0.setPointer(at: 0x98, to: 0x100)
            $0.setString("TestCharacter", at: 0x1A0, storage: 0x300)
            $0.setString("TestRig.hkx", at: 0x1A8, storage: 0x320)
            $0.setString("TestRagdoll.hkx", at: 0x1B0, storage: 0x340)
        }
        #expect(data.name == "TestCharacter")
        #expect(data.rigName == "TestRig.hkx")
        #expect(data.ragdollName == "TestRagdoll.hkx")
    }
}
