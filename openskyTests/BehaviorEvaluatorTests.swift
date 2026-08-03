// The behavior graph instance (issue #187): variables, bindings, and events.
// Synthetic graphs built in code — no packfile bytes and no install
// (AGENTS.md "Legal & IP boundary").
//
// Node lifecycle and determinism are in BehaviorLifecycleTests.swift; generator
// semantics in BehaviorGeneratorTests.swift and BehaviorClipTests.swift.

import Foundation
@testable import opensky
import simd
import Testing

struct BehaviorEvaluatorTests {
    // MARK: - Variables

    @Test func seedsVariablesFromTheDeclaredInitialValues() {
        let data = BehaviorFixture.graphData(variables: [
            BehaviorVariableSpec("Speed", .real, 3.5),
            BehaviorVariableSpec("iState", .int32, 7),
            BehaviorVariableSpec("bIsSprinting", .bool, 1)
        ])
        let graph = BehaviorFixture.instance(root: nil, table: BehaviorObjectTable(), data: data)
        #expect(graph.variable(named: "Speed")?.realValue == 3.5)
        #expect(graph.variable(named: "iState")?.intValue == 7)
        #expect(graph.variable(named: "bIsSprinting")?.boolValue == true)
        #expect(graph.variable(named: "NotDeclared") == nil)
    }

    @Test func setsVariablesByNameAndCoercesToTheDeclaredType() {
        let data = BehaviorFixture.graphData(variables: [
            BehaviorVariableSpec("Speed", .real, 0),
            BehaviorVariableSpec("bFlag", .bool, 0)
        ])
        let graph = BehaviorFixture.instance(root: nil, table: BehaviorObjectTable(), data: data)
        #expect(graph.setVariable(.real(12.25), named: "Speed"))
        #expect(graph.variable(named: "Speed")?.realValue == 12.25)

        // A real written into a bool lands as true, and reads back as a bool.
        #expect(graph.setVariable(.real(0.5), named: "bFlag"))
        #expect(graph.variable(named: "bFlag") == .bool(true))

        #expect(!graph.setVariable(.real(1), named: "NotDeclared"))
    }

    @Test func twoInstancesOverTheSameDeclarationsDoNotShareVariables() {
        let data = BehaviorFixture.graphData(variables: [BehaviorVariableSpec("Speed", .real, 1)])
        let first = BehaviorFixture.instance(root: nil, table: BehaviorObjectTable(), data: data)
        let second = BehaviorFixture.instance(root: nil, table: BehaviorObjectTable(), data: data)
        first.setVariable(.real(99), named: "Speed")
        #expect(first.variable(named: "Speed")?.realValue == 99)
        #expect(second.variable(named: "Speed")?.realValue == 1)
    }

    // MARK: - Bindings

    @Test func bindingRewritesTheSelectedGeneratorIndex() {
        let data = BehaviorFixture.graphData(variables: [BehaviorVariableSpec(
            "iSelect",
            .int32,
            0
        )])
        var table = BehaviorObjectTable()
        let first = table.add(
            BehaviorFixture.clipGenerator("first", animationName: "left"), at: 0x100
        )
        let second = table.add(
            BehaviorFixture.clipGenerator("second", animationName: "right"), at: 0x200
        )
        let binding = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("m_selectedGeneratorIndex", 0)]),
            at: 0x300
        )
        let root = table.add(
            BehaviorFixture.selector(
                "select", generators: [first, second], selected: 0, bindingSet: binding
            ),
            at: 0x400
        )
        let clips = BehaviorClipTable(byName: [
            "left": BehaviorStaticClip(samples: [BehaviorFixture.sample(bone: 1, x: 1)]),
            "right": BehaviorStaticClip(samples: [BehaviorFixture.sample(bone: 1, x: 2)])
        ])
        let graph = BehaviorFixture.instance(root: root, table: table, data: data, clips: clips)

        #expect(graph.update(deltaTime: 1 / 30).bones[1].translation.x == 1)
        graph.setVariable(.int(1), named: "iSelect")
        #expect(graph.update(deltaTime: 1 / 30).bones[1].translation.x == 2)
    }

    @Test func enableBindingDisablesTheNodeItSitsOn() {
        let data = BehaviorFixture.graphData(variables: [BehaviorVariableSpec(
            "bEnabled",
            .bool,
            1
        )])
        var table = BehaviorObjectTable()
        let binding = table.add(
            BehaviorFixture.bindingSet(
                [BehaviorBindingSpec("m_playbackSpeed", 0)], indexOfBindingToEnable: 0
            ),
            at: 0x100
        )
        let root = table.add(
            BehaviorFixture.clipGenerator(
                "clip", animationName: "held", bindingSet: binding
            ),
            at: 0x200
        )
        let clips = BehaviorClipTable(
            byName: ["held": BehaviorStaticClip(samples: [BehaviorFixture.sample(bone: 1, x: 5)])]
        )
        let graph = BehaviorFixture.instance(root: root, table: table, data: data, clips: clips)

        #expect(graph.update(deltaTime: 1 / 30).bones[1].translation.x == 5)
        graph.setVariable(.bool(false), named: "bEnabled")
        let disabled = graph.update(deltaTime: 1 / 30)
        #expect(disabled.bones[1] == BehaviorFixture.skeleton().referencePose[1])
        #expect(graph.tally.featureGaps["disabledNode"] == 1)
    }

    @Test func aCharacterPropertyBindingIsTalliedRatherThanGuessed() {
        let data = BehaviorFixture.graphData(variables: [BehaviorVariableSpec("Speed", .real, 1)])
        var table = BehaviorObjectTable()
        let bindingSet = HKBVariableBindingSet(
            bindings: [HKBVariableBinding(
                memberPath: "m_playbackSpeed",
                variableIndex: 0,
                bitIndex: -1,
                bindingType: 1
            )],
            indexOfBindingToEnable: -1,
            unresolved: []
        )
        let binding = table.add(bindingSet, at: 0x100)
        let root = table.add(
            BehaviorFixture.clipGenerator(
                "clip", animationName: "none", bindingSet: binding
            ),
            at: 0x200
        )
        let graph = BehaviorFixture.instance(root: root, table: table, data: data)
        graph.update(deltaTime: 1 / 30)
        #expect(graph.tally.unappliedBindings["m_playbackSpeed"] == 1)
    }

    // MARK: - Events

    @Test func anEventIsVisibleToTheNextUpdateOnly() {
        let data = BehaviorFixture.graphData(events: ["idleStart", "idleStop"])
        let graph = BehaviorFixture.instance(root: nil, table: BehaviorObjectTable(), data: data)
        #expect(graph.raiseEvent(named: "idleStart"))
        #expect(!graph.raiseEvent(named: "notDeclared"))

        let first = graph.update(deltaTime: 1 / 30)
        #expect(first.firedEvents.map(\.name) == ["idleStart"])
        let second = graph.update(deltaTime: 1 / 30)
        #expect(second.firedEvents.isEmpty)
    }

    @Test func eventsFireInRaiseOrder() {
        let data = BehaviorFixture.graphData(events: ["one", "two", "three"])
        let graph = BehaviorFixture.instance(root: nil, table: BehaviorObjectTable(), data: data)
        graph.raiseEvent(named: "three")
        graph.raiseEvent(named: "one")
        graph.raiseEvent(named: "two")
        #expect(
            graph.update(deltaTime: 1 / 30).firedEvents.map(\.name)
                == ["three", "one", "two"]
        )
    }

    @Test func eventPayloadsSurviveTheQueue() {
        let data = BehaviorFixture.graphData(events: ["sound"])
        let graph = BehaviorFixture.instance(root: nil, table: BehaviorObjectTable(), data: data)
        graph.raiseEvent(named: "sound", payload: "footstep")
        #expect(graph.update(deltaTime: 1 / 30).firedEvents.first?.payload == "footstep")
    }
}
