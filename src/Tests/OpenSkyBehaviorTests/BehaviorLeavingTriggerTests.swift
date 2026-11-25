// The clip triggers that take a graph out of the state an event enters. One machine
// holds an idle state and an exit state. The exit clip sends `Leave` and `Other`; only
// `Leave` has a transition out of the exit state (docs/engine/vehicles.md#how-an-exit-state-ends).

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import Testing

struct BehaviorLeavingTriggerTests {
    private static let behaviorGraph = 0x000
    private static let graphData = 0x0A0
    private static let stringData = 0x120
    private static let namePointers = 0x160
    private static let nameStrings = [0x180, 0x190, 0x1A0, 0x1B0]
    private static let machine = 0x1C0
    private static let statePointers = 0x270
    private static let idleState = 0x280
    private static let exitState = 0x300
    private static let idleClip = 0x380
    private static let exitClip = 0x400
    private static let triggerArray = 0x480
    private static let triggerElements = 0x4A0
    private static let wildcardArray = 0x4E0
    private static let wildcardElements = 0x500
    private static let exitTransitions = 0x590
    private static let exitTransitionElements = 0x5B0
    private static let idleName = 0x600
    private static let exitName = 0x620

    /// Event ids: 0 `Enter`, 1 `Leave`, 2 `Global`, 3 `Other`.
    private static func graph() throws -> HKXObjectGraph {
        var fixture = HKBNodeFixture(payloadSize: 0x680)
        fixture.addObject("hkbBehaviorGraph", at: behaviorGraph)
        fixture.addObject("hkbBehaviorGraphData", at: graphData)
        fixture.addObject("hkbBehaviorGraphStringData", at: stringData)
        fixture.addObject("hkbStateMachine", at: machine)
        fixture.addObject("hkbStateMachineStateInfo", at: idleState)
        fixture.addObject("hkbStateMachineStateInfo", at: exitState)
        fixture.addObject("hkbClipGenerator", at: idleClip)
        fixture.addObject("hkbClipGenerator", at: exitClip)
        fixture.addObject("hkbClipTriggerArray", at: triggerArray)
        fixture.addObject("hkbStateMachineTransitionInfoArray", at: wildcardArray)
        fixture.addObject("hkbStateMachineTransitionInfoArray", at: exitTransitions)

        fixture.setPointer(at: behaviorGraph + 0x80, to: machine)
        fixture.setPointer(at: behaviorGraph + 0x88, to: graphData)
        fixture.setPointer(at: graphData + 0x78, to: stringData)
        fixture.setArray(at: stringData + 0x10, count: 4, dataOffset: namePointers)
        for (index, name) in ["Enter", "Leave", "Global", "Other"].enumerated() {
            fixture.setString(name, at: namePointers + index * 8, storage: nameStrings[index])
        }

        fixture.setInt32(0, at: machine + 0x68)
        fixture.setPointerArray(
            at: machine + 0x90, dataOffset: statePointers, targets: [idleState, exitState]
        )
        fixture.setPointer(at: machine + 0xA0, to: wildcardArray)
        writeState(&fixture, at: idleState, id: 0, generator: idleClip)
        writeState(&fixture, at: exitState, id: 1, generator: exitClip)
        fixture.setPointer(at: exitState + 0x50, to: exitTransitions)

        fixture.setString("idle.hkx", at: idleClip + 0x48, storage: idleName)
        fixture.setUInt8(1, at: idleClip + 0x72)
        fixture.setString("exit.hkx", at: exitClip + 0x48, storage: exitName)
        fixture.setPointer(at: exitClip + 0x50, to: triggerArray)
        fixture.setArray(at: triggerArray + 0x10, count: 2, dataOffset: triggerElements)
        writeTrigger(&fixture, index: 0, event: 1, time: 3)
        writeTrigger(&fixture, index: 1, event: 3, time: 1)

        fixture.setArray(at: wildcardArray + 0x10, count: 2, dataOffset: wildcardElements)
        writeTransition(&fixture, at: wildcardElements, Transition(event: 0, to: 1, flags: 0))
        writeTransition(
            &fixture, at: wildcardElements + HKBStateMachineTransitionInfo.stride,
            Transition(event: 2, to: 0, flags: Int16(BehaviorTransitionFlag.globalWildcard))
        )
        fixture.setArray(at: exitTransitions + 0x10, count: 1, dataOffset: exitTransitionElements)
        writeTransition(&fixture, at: exitTransitionElements, Transition(event: 1, to: 0, flags: 0))
        return try fixture.buildGraph()
    }

    private static func writeState(
        _ fixture: inout HKBNodeFixture, at base: Int, id: Int32, generator: Int
    ) {
        fixture.setPointer(at: base + 0x58, to: generator)
        fixture.setInt32(id, at: base + 0x68)
        fixture.setBool(true, at: base + 0x70)
    }

    private static func writeTrigger(
        _ fixture: inout HKBNodeFixture, index: Int, event: Int32, time: Float
    ) {
        let base = triggerElements + index * HKBClipTrigger.stride
        fixture.setFloat(time, at: base + 0x00)
        fixture.setInt32(event, at: base + 0x08)
    }

    private struct Transition {
        let event: Int32
        let to: Int32
        let flags: Int16
    }

    private static func writeTransition(
        _ fixture: inout HKBNodeFixture, at base: Int,
        _ transition: Transition
    ) {
        fixture.setInt32(transition.event, at: base + 0x30)
        fixture.setInt32(transition.to, at: base + 0x34)
        fixture.setInt16(transition.flags, at: base + 0x42)
    }

    private static func index() throws -> BehaviorEventClipIndex {
        let graph = try Self.graph()
        return BehaviorEventClipIndex { $0 == "test.hkx" ? graph : nil }
    }

    @Test func theExitClipLeavesOnTheTriggerWithATransitionOutOfItsState() throws {
        let index = try Self.index()
        let clip = try #require(index.clip(forEvent: "Enter", behaviorFile: "test.hkx"))
        #expect(clip.animationName == "exit.hkx")
        #expect(clip.triggers.map(\.name) == ["Leave", "Other"])
        #expect(clip.leavingEvents == ["enter", "leave", "global"])
        #expect(clip.leavingTriggers.map(\.name) == ["Leave"])
        #expect(clip.leavingTriggers.first?.time == 3)
    }

    @Test func aStateLeavesOnlyOnTheTransitionsAboveIt() throws {
        let index = try Self.index()
        _ = index.clip(forEvent: "Enter", behaviorFile: "test.hkx")
        let clip = try #require(index.clip(forEvent: "Global", behaviorFile: "test.hkx"))
        #expect(clip.animationName == "idle.hkx")
        #expect(clip.leavingEvents == ["enter", "global"])
        #expect(clip.leavingTriggers.isEmpty)
        #expect(index.parents.count == 1)
    }
}
