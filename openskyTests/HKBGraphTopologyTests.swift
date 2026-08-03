// Structural decode tests for the behavior node classes (todo 14.2) over one
// hand-built synthetic packfile — never an extracted game file (AGENTS.md
// "Legal & IP boundary"). Every name and number below is invented; only the
// member offsets come from the class layouts in
// docs/formats/hkx-behavior-nodes.md.
//
// HKBNodeClassTests proves each class survives a zeroed, a truncated, and a
// dangling-pointer object. This file proves the offsets themselves: a state
// machine whose state names, transitions, blend weights, and clip paths all
// come back with the values the fixture wrote, and a walk that reaches every
// object through the registry rather than through a hand-written switch.

import Foundation
@testable import opensky
import Testing

/// One behavior graph: state machine -> state -> blender -> child -> clip, plus
/// a wildcard transition array, a transition effect, a clip trigger array, and
/// a variable binding set. Objects sit on 0x20 boundaries so an assertion can
/// name the byte it reads.
enum HKBGraphFixture {
    // Object bases inside the __data__ payload.
    static let stateMachine = 0x000
    static let stateInfo = 0x120
    static let clipGenerator = 0x1A0
    static let blenderGenerator = 0x2C0
    static let blenderChild = 0x380
    static let transitionArray = 0x3E0
    static let transitionEffect = 0x450
    static let clipTriggerArray = 0x4E0
    static let bindingSet = 0x600

    // Element data and string storage the fixups target.
    private static let transitionElements = 0x400
    private static let triggerElements = 0x500
    private static let statePointers = 0x520
    private static let childPointers = 0x530
    private static let machineNameString = 0x540
    private static let stateNameString = 0x560
    private static let clipNodeNameString = 0x580
    private static let animationNameString = 0x5A0
    private static let blenderNameString = 0x5C0
    private static let memberPathString = 0x5E0
    private static let bindingElements = 0x640
    private static let payloadSize = 0x700

    // Authored values every assertion checks against.
    static let machineName = "TestStateMachine"
    static let stateName = "WalkState"
    static let clipNodeName = "ClipNode"
    static let animationName = "test_walk_forward.hkx"
    static let blenderName = "BlendNode"
    static let memberPath = "m_blendParameter"
    static let stateId: Int32 = 3
    static let startStateId: Int32 = 3
    static let syncVariableIndex: Int32 = 5
    static let stateProbability: Float = 0.75
    static let playbackSpeed: Float = 1.5
    static let animationBindingIndex: Int16 = 12
    static let blendParameter: Float = 0.25
    static let childWeight: Float = 0.5
    static let childWorldFromModelWeight: Float = 0.25
    static let transitionEventId: Int32 = 9
    static let transitionPriority: Int16 = 2
    static let transitionDuration: Float = 0.2
    static let triggerLocalTime: Float = 0.33
    static let triggerEventId: Int32 = 21
    static let boundVariableIndex: Int32 = 4

    static func graph() throws -> HKXObjectGraph {
        var fixture = HKBNodeFixture(payloadSize: payloadSize)
        fixture.addObject("hkbStateMachine", at: stateMachine)
        fixture.addObject("hkbStateMachineStateInfo", at: stateInfo)
        fixture.addObject("hkbClipGenerator", at: clipGenerator)
        fixture.addObject("hkbBlenderGenerator", at: blenderGenerator)
        fixture.addObject("hkbBlenderGeneratorChild", at: blenderChild)
        fixture.addObject("hkbStateMachineTransitionInfoArray", at: transitionArray)
        fixture.addObject("hkbBlendingTransitionEffect", at: transitionEffect)
        fixture.addObject("hkbClipTriggerArray", at: clipTriggerArray)
        fixture.addObject("hkbVariableBindingSet", at: bindingSet)

        writeStateMachine(&fixture)
        writeStateInfo(&fixture)
        writeClipGenerator(&fixture)
        writeBlender(&fixture)
        writeTransitions(&fixture)
        writeTriggers(&fixture)
        writeBindingSet(&fixture)
        return try fixture.buildGraph()
    }

    private static func writeStateMachine(_ fixture: inout HKBNodeFixture) {
        let base = stateMachine
        fixture.setPointer(at: base + 0x10, to: bindingSet)
        fixture.setUInt64(0x1234, at: base + 0x30)
        fixture.setString(machineName, at: base + 0x38, storage: machineNameString)
        fixture.setInt32(7, at: base + 0x48) // m_eventToSendWhenStateOrTransitionChanges
        fixture.setInt32(startStateId, at: base + 0x68)
        fixture.setInt32(syncVariableIndex, at: base + 0x7C)
        fixture.setBool(true, at: base + 0x84) // m_wrapAroundStateId
        fixture.setUInt8(2, at: base + 0x86) // m_startStateMode
        fixture.setPointerArray(
            at: base + 0x90, dataOffset: statePointers, targets: [stateInfo]
        )
        fixture.setPointer(at: base + 0xA0, to: transitionArray)
    }

    private static func writeStateInfo(_ fixture: inout HKBNodeFixture) {
        let base = stateInfo
        fixture.setPointer(at: base + 0x50, to: transitionArray)
        fixture.setPointer(at: base + 0x58, to: blenderGenerator)
        fixture.setString(stateName, at: base + 0x60, storage: stateNameString)
        fixture.setInt32(stateId, at: base + 0x68)
        fixture.setFloat(stateProbability, at: base + 0x6C)
        fixture.setBool(true, at: base + 0x70)
    }

    private static func writeClipGenerator(_ fixture: inout HKBNodeFixture) {
        let base = clipGenerator
        fixture.setString(clipNodeName, at: base + 0x38, storage: clipNodeNameString)
        fixture.setString(animationName, at: base + 0x48, storage: animationNameString)
        fixture.setPointer(at: base + 0x50, to: clipTriggerArray)
        fixture.setFloat(playbackSpeed, at: base + 0x64)
        fixture.setInt16(animationBindingIndex, at: base + 0x70)
        fixture.setUInt8(1, at: base + 0x72) // m_mode: loop
        fixture.setUInt8(4, at: base + 0x73) // m_flags: mirror
    }

    private static func writeBlender(_ fixture: inout HKBNodeFixture) {
        let base = blenderGenerator
        fixture.setString(blenderName, at: base + 0x38, storage: blenderNameString)
        fixture.setFloat(blendParameter, at: base + 0x4C)
        fixture.setInt16(1, at: base + 0x58) // m_indexOfSyncMasterChild
        fixture.setPointerArray(
            at: base + 0x60, dataOffset: childPointers, targets: [blenderChild]
        )
        fixture.setPointer(at: blenderChild + 0x30, to: clipGenerator)
        fixture.setFloat(childWeight, at: blenderChild + 0x40)
        fixture.setFloat(childWorldFromModelWeight, at: blenderChild + 0x44)
    }

    private static func writeTransitions(_ fixture: inout HKBNodeFixture) {
        fixture.setArray(
            at: transitionArray + 0x10, count: 1, dataOffset: transitionElements
        )
        let element = transitionElements
        fixture.setInt32(11, at: element + 0x00) // m_triggerInterval.m_enterEventId
        fixture.setPointer(at: element + 0x20, to: transitionEffect)
        fixture.setInt32(transitionEventId, at: element + 0x30)
        fixture.setInt32(stateId, at: element + 0x34) // m_toStateId
        fixture.setInt16(transitionPriority, at: element + 0x40)

        fixture.setFloat(transitionDuration, at: transitionEffect + 0x50)
        fixture.setUInt32(3, at: transitionEffect + 0x58) // m_flags, 16-bit field
        fixture.setUInt8(1, at: transitionEffect + 0x5B) // m_blendCurve: linear
    }

    private static func writeTriggers(_ fixture: inout HKBNodeFixture) {
        fixture.setArray(
            at: clipTriggerArray + 0x10, count: 1, dataOffset: triggerElements
        )
        fixture.setFloat(triggerLocalTime, at: triggerElements + 0x00)
        fixture.setInt32(triggerEventId, at: triggerElements + 0x08)
        fixture.setBool(true, at: triggerElements + 0x18)
    }

    private static func writeBindingSet(_ fixture: inout HKBNodeFixture) {
        fixture.setArray(at: bindingSet + 0x10, count: 1, dataOffset: bindingElements)
        fixture.setInt32(-1, at: bindingSet + 0x20)
        fixture.setString(
            memberPath, at: bindingElements + 0x00, storage: memberPathString
        )
        fixture.setInt32(boundVariableIndex, at: bindingElements + 0x1C)
        fixture.setUInt8(0xFF, at: bindingElements + 0x20) // m_bitIndex: -1
    }
}

struct HKBGraphTopologyTests {
    private static func target(_ offset: Int) -> HKXPointerTarget {
        HKXPointerTarget(sectionIndex: HKBNodeFixture.dataSection, dataOffset: offset)
    }

    @Test
    func decodesTheStateMachineAndItsState() throws {
        let graph = try HKBGraphFixture.graph()
        let machine = try #require(HKBStateMachine.decode(
            at: Self.target(HKBGraphFixture.stateMachine), in: graph
        ))
        #expect(machine.nodeName == HKBGraphFixture.machineName)
        #expect(machine.node.userData == 0x1234)
        #expect(machine.eventToSendWhenStateOrTransitionChanges.id == 7)
        #expect(machine.startStateId == Int(HKBGraphFixture.startStateId))
        #expect(machine.syncVariableIndex == Int(HKBGraphFixture.syncVariableIndex))
        #expect(machine.wrapAroundStateId)
        #expect(machine.startStateMode == 2)
        #expect(machine.states.count == 1)
        #expect(machine.wildcardTransitions == Self.target(HKBGraphFixture.transitionArray))

        let stateTarget = try #require(machine.states.compactMap(\.self).first)
        let state = try #require(HKBStateMachineStateInfo.decode(at: stateTarget, in: graph))
        #expect(state.name == HKBGraphFixture.stateName)
        #expect(state.stateId == Int(HKBGraphFixture.stateId))
        #expect(state.probability == HKBGraphFixture.stateProbability)
        #expect(state.enable)
        #expect(state.generator == Self.target(HKBGraphFixture.blenderGenerator))
    }

    @Test
    func decodesTransitionsAndTheirEffect() throws {
        let graph = try HKBGraphFixture.graph()
        let array = try #require(HKBStateMachineTransitionInfoArray.decode(
            at: Self.target(HKBGraphFixture.transitionArray), in: graph
        ))
        let transition = try #require(array.transitions.first)
        #expect(array.transitions.count == 1)
        #expect(transition.triggerInterval.enterEventId == 11)
        #expect(transition.eventId == Int(HKBGraphFixture.transitionEventId))
        #expect(transition.toStateId == Int(HKBGraphFixture.stateId))
        #expect(transition.priority == Int(HKBGraphFixture.transitionPriority))
        #expect(transition.transition == Self.target(HKBGraphFixture.transitionEffect))

        let effect = try #require(HKBBlendingTransitionEffect.decode(
            at: Self.target(HKBGraphFixture.transitionEffect), in: graph
        ))
        #expect(effect.duration == HKBGraphFixture.transitionDuration)
        #expect(effect.flags == 3)
        #expect(effect.blendCurve == 1)
    }

    @Test
    func decodesTheBlenderItsChildAndTheClip() throws {
        let graph = try HKBGraphFixture.graph()
        let blender = try #require(HKBBlenderGenerator.decode(
            at: Self.target(HKBGraphFixture.blenderGenerator), in: graph
        ))
        #expect(blender.nodeName == HKBGraphFixture.blenderName)
        #expect(blender.blender.blendParameter == HKBGraphFixture.blendParameter)
        #expect(blender.blender.indexOfSyncMasterChild == 1)
        #expect(blender.blender.children.count == 1)

        let childTarget = try #require(blender.blender.children.compactMap(\.self).first)
        let child = try #require(HKBBlenderGeneratorChild.decode(at: childTarget, in: graph))
        #expect(child.weight == HKBGraphFixture.childWeight)
        #expect(child.worldFromModelWeight == HKBGraphFixture.childWorldFromModelWeight)

        let clipTarget = try #require(child.generator)
        let clip = try #require(HKBClipGenerator.decode(at: clipTarget, in: graph))
        #expect(clip.nodeName == HKBGraphFixture.clipNodeName)
        #expect(clip.animationName == HKBGraphFixture.animationName)
        #expect(clip.playbackSpeed == HKBGraphFixture.playbackSpeed)
        #expect(clip.animationBindingIndex == Int(HKBGraphFixture.animationBindingIndex))
        #expect(clip.mode == 1)
        #expect(clip.flags == 4)

        let triggers = try #require(HKBClipTriggerArray.decode(
            at: Self.target(HKBGraphFixture.clipTriggerArray), in: graph
        ))
        let trigger = try #require(triggers.triggers.first)
        #expect(trigger.localTime == HKBGraphFixture.triggerLocalTime)
        #expect(trigger.event.id == Int(HKBGraphFixture.triggerEventId))
        #expect(trigger.relativeToEndOfClip)
    }

    @Test
    func decodesTheVariableBinding() throws {
        let graph = try HKBGraphFixture.graph()
        let set = try #require(HKBVariableBindingSet.decode(
            at: Self.target(HKBGraphFixture.bindingSet), in: graph
        ))
        let binding = try #require(set.bindings.first)
        #expect(set.indexOfBindingToEnable == -1)
        #expect(binding.memberPath == HKBGraphFixture.memberPath)
        #expect(binding.variableIndex == Int(HKBGraphFixture.boundVariableIndex))
        #expect(binding.bitIndex == -1)
        #expect(binding.bindingType == 0)
    }

    /// The walk is the generic path the 14.3 evaluator and the CLI take: it
    /// follows `references` through the registry and never names a class.
    @Test
    func walksTheWholeGraphThroughTheRegistry() throws {
        let graph = try HKBGraphFixture.graph()
        let topology = HKBGraphTopology.walk(
            from: Self.target(HKBGraphFixture.stateMachine), in: graph
        )
        let reached = Set(topology.nodes.map(\.object.className))
        #expect(reached == [
            "hkbStateMachine",
            "hkbVariableBindingSet",
            "hkbStateMachineStateInfo",
            "hkbStateMachineTransitionInfoArray",
            "hkbBlendingTransitionEffect",
            "hkbBlenderGenerator",
            "hkbBlenderGeneratorChild",
            "hkbClipGenerator",
            "hkbClipTriggerArray"
        ])
        #expect(topology.skippedClassCounts.isEmpty)
        #expect(topology.unregisteredTargetCount == 0)
        // Shared objects are decoded once: the transition array is reached both
        // as the machine's wildcard list and as the state's own transitions.
        #expect(topology.nodes.count == reached.count)
        // Depth is first-visit depth from the root generator.
        let clip = try #require(topology.nodes(ofClass: "hkbClipGenerator").first)
        #expect(clip.depth == 4)
    }

    @Test
    func decodesEveryRegisteredObjectInTheFile() throws {
        let graph = try HKBGraphFixture.graph()
        let report = HKBDecodeReport.decodeAll(in: graph)
        #expect(report.decodedTotal == 9)
        #expect(report.skippedTotal == 0)
        #expect(report.failedTotal == 0)
        #expect(report.uncoveredClassNames.isEmpty)
        let misreads = report.unresolved.filter { $0.miss != .noFixup }
        #expect(misreads.isEmpty, "\(misreads.map { "\($0.field) \($0.miss.rawValue)" })")
    }

    /// A class the registry does not know is a recorded skip, not a crash and
    /// not a silent drop — the tally the milestone rule measures.
    @Test
    func recordsAnUnknownClassAsASkip() throws {
        var fixture = HKBNodeFixture(payloadSize: 0x80)
        fixture.addObject("hkbClipGenerator", at: 0x00)
        fixture.addObject("hkbFutureModifierNotYetDecoded", at: 0x40)
        let graph = try fixture.buildGraph()
        let report = HKBDecodeReport.decodeAll(in: graph)
        #expect(report.skippedCounts["hkbFutureModifierNotYetDecoded"] == 1)
        #expect(report.uncoveredClassNames == ["hkbFutureModifierNotYetDecoded"])
    }
}
