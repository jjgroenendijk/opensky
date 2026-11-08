// The modifiers that compute variables: each reads its bound inputs and writes its
// outputs back to the variables bound to them. All graphs are synthetic.

import Foundation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import simd
import Testing

struct BehaviorVariableModifierTests {
    /// A graph whose root runs `modifier` over the reference pose, with
    /// `bindings` on the modifier.
    private func graph(
        running modifier: (HKXPointerTarget?) -> any HKBClass,
        bindings: [BehaviorBindingSpec],
        variables: [BehaviorVariableSpec],
        events: [String] = [],
        extra: (inout BehaviorObjectTable) -> Void = { _ in }
    ) -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        extra(&table)
        let set = table.add(BehaviorFixture.bindingSet(bindings), at: 0x100)
        let node = table.add(modifier(set), at: 0x110)
        let root = table.add(
            BehaviorFixture.modifierGenerator("root", modifier: node, generator: nil), at: 0x120
        )
        return BehaviorFixture.instance(
            root: root, table: table,
            data: BehaviorFixture.graphData(variables: variables, events: events)
        )
    }

    private func firedNames(
        _ graph: BehaviorGraphInstance,
        updates: Int,
        step: Float = 0.05
    ) -> [String] {
        (0 ..< updates).flatMap { _ in
            graph.update(deltaTime: step).firedEvents.compactMap(\.name)
        }
    }

    @Test func expressionAssignsVariablesInOrder() {
        let graph = graph(
            running: { set in
                HKBEvaluateExpressionModifier(
                    modifier: BehaviorFixture.modifierHeader("expr", bindingSet: set),
                    expressions: BehaviorFixture.target(0x200), unresolved: []
                )
            },
            bindings: [],
            variables: [
                BehaviorVariableSpec("TurnDelta", .real, -45),
                BehaviorVariableSpec("turnSpeed", .real, 0),
                BehaviorVariableSpec("doubled", .real, 0)
            ],
            extra: { table in
                table.add(HKBExpressionDataArray(expressionsData: [
                    HKBExpressionData(
                        expression: "turnSpeed = fabs(TurnDelta/90)", assignmentVariableIndex: -1,
                        assignmentEventIndex: -1, eventMode: 0
                    ),
                    HKBExpressionData(
                        expression: "doubled = turnSpeed * 2 + cond(TurnDelta < 0, 1, 0)",
                        assignmentVariableIndex: -1, assignmentEventIndex: -1, eventMode: 0
                    )
                ], unresolved: []), at: 0x200)
            }
        )
        graph.update(deltaTime: 0.05)
        #expect(graph.variable(named: "turnSpeed") == .real(0.5))
        #expect(graph.variable(named: "doubled") == .real(2))
    }

    @Test func expressionEventModesDifferInHowOftenTheyFire() {
        let modes = [0, 1, 2]
        let graph = graph(
            running: { set in
                HKBEvaluateExpressionModifier(
                    modifier: BehaviorFixture.modifierHeader("expr", bindingSet: set),
                    expressions: BehaviorFixture.target(0x200), unresolved: []
                )
            },
            bindings: [],
            variables: [BehaviorVariableSpec("iStance", .int32, 1)],
            events: ["once", "onTrue", "rising"],
            extra: { table in
                table.add(
                    HKBExpressionDataArray(
                        expressionsData: zip(["once", "onTrue", "rising"], modes).map {
                            HKBExpressionData(
                                expression: "\($0) if (iStance == 1)", assignmentVariableIndex: -1,
                                assignmentEventIndex: -1, eventMode: $1
                            )
                        },
                        unresolved: []
                    ),
                    at: 0x200
                )
            }
        )
        var fired = firedNames(graph, updates: 3)
        graph.setVariable(.int(0), named: "iStance")
        fired += firedNames(graph, updates: 1)
        graph.setVariable(.int(1), named: "iStance")
        // An event raised in one update is reported by the next.
        fired += firedNames(graph, updates: 2)
        #expect(fired.count { $0 == "once" } == 1)
        #expect(fired.count { $0 == "onTrue" } == 4)
        #expect(fired.count { $0 == "rising" } == 2)
    }

    @Test func isActiveWritesTrueWhileRunningAndFalseAfter() {
        var table = BehaviorObjectTable()
        let set = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("bIsActive0", 1)]),
            at: 0x100
        )
        let active = table.add(BSIsActiveModifier(
            modifier: BehaviorFixture.modifierHeader("active", bindingSet: set),
            isActive: Array(repeating: false, count: 5),
            invertActive: Array(repeating: false, count: 5), unresolved: []
        ), at: 0x110)
        let wrapped = table.add(
            BehaviorFixture.modifierGenerator("wrapped", modifier: active, generator: nil),
            at: 0x120
        )
        let other = table.add(
            BehaviorFixture.clipGenerator("other", animationName: "left"),
            at: 0x130
        )
        let selectSet = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("m_selectedGeneratorIndex", 0)]),
            at: 0x140
        )
        let root = table.add(
            BehaviorFixture.selector("select", generators: [wrapped, other], bindingSet: selectSet),
            at: 0x150
        )
        let graph = BehaviorFixture.instance(
            root: root, table: table,
            data: BehaviorFixture.graphData(variables: [
                BehaviorVariableSpec("iSelect", .int32, 0), BehaviorVariableSpec(
                    "bActive",
                    .bool,
                    0
                )
            ]),
            clips: BehaviorFixture.staticClipPair(left: 1, right: 2)
        )
        graph.update(deltaTime: 0.05)
        #expect(graph.variable(named: "bActive") == .bool(true))
        graph.setVariable(.int(1), named: "iSelect")
        graph.update(deltaTime: 0.05)
        graph.update(deltaTime: 0.05)
        #expect(graph.variable(named: "bActive") == .bool(false))
    }

    @Test func interpolationMovesResultTowardsTarget() {
        let graph = graph(
            running: { set in
                BSInterpValueModifier(
                    modifier: BehaviorFixture.modifierHeader("interp", bindingSet: set),
                    source: 0, target: 0, result: 0, gain: 10, unresolved: []
                )
            },
            bindings: [
                BehaviorBindingSpec("source", 0), BehaviorBindingSpec("result", 0),
                BehaviorBindingSpec("target", 1)
            ],
            variables: [
                BehaviorVariableSpec("value", .real, 0),
                BehaviorVariableSpec("goal", .real, 1)
            ]
        )
        graph.update(deltaTime: 0.05)
        #expect(graph.variable(named: "value") == .real(0.5))
        graph.update(deltaTime: 0.05)
        #expect(graph.variable(named: "value") == .real(0.75))
    }

    @Test func eventsFromRangeFireOnEnteringABand() {
        let graph = graph(
            running: { set in
                HKBEventsFromRangeModifier(
                    modifier: BehaviorFixture.modifierHeader("range", bindingSet: set),
                    inputValue: 0, lowerBound: 0, eventRanges: BehaviorFixture.target(0x200),
                    unresolved: []
                )
            },
            bindings: [BehaviorBindingSpec("inputValue", 0)],
            variables: [BehaviorVariableSpec("speed", .real, 0.5)],
            events: ["slow", "fast"],
            extra: { table in
                table.add(HKBEventRangeDataArray(eventData: [
                    HKBEventRangeData(
                        upperBound: 1,
                        event: HKBEventProperty(id: 0, payload: nil),
                        eventMode: 0
                    ),
                    HKBEventRangeData(
                        upperBound: 2,
                        event: HKBEventProperty(id: 1, payload: nil),
                        eventMode: 0
                    )
                ], unresolved: []), at: 0x200)
            }
        )
        var fired = firedNames(graph, updates: 3)
        graph.setVariable(.real(1.5), named: "speed")
        fired += firedNames(graph, updates: 3)
        #expect(fired == ["slow", "fast"])
    }

    @Test func repeatingTimerFiresEveryAlarm() {
        let graph = graph(
            running: { set in
                BSTimerModifier(
                    modifier: BehaviorFixture.modifierHeader("timer", bindingSet: set),
                    alarmTimeSeconds: 0.09, alarmEvent: HKBEventProperty(id: 0, payload: nil),
                    resetAlarm: true, unresolved: []
                )
            },
            bindings: [],
            variables: [],
            events: ["alarm"]
        )
        #expect(firedNames(graph, updates: 9).count == 4)
    }
}

extension BehaviorVariableModifierTests {
    @Test func vectorModifiersWriteTheirOutputs() {
        let decompose = graph(
            running: { set in
                BSDecomposeVectorModifier(
                    modifier: BehaviorFixture.modifierHeader("split", bindingSet: set),
                    vector: SIMD4(3, 4, 5, 0), components: SIMD4(), unresolved: []
                )
            },
            bindings: [BehaviorBindingSpec("y", 0)],
            variables: [BehaviorVariableSpec("outY", .real, 0)]
        )
        decompose.update(deltaTime: 0.05)
        #expect(decompose.variable(named: "outY") == .real(4))

        let transform = graph(
            running: { set in
                HKBTransformVectorModifier(
                    modifier: BehaviorFixture.modifierHeader("turn", bindingSet: set),
                    rotation: simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)).vector,
                    translation: SIMD4(0, 0, 10, 0), vectorIn: SIMD4(1, 0, 0, 0),
                    vectorOut: SIMD4(),
                    rotateOnly: false, inverse: false, computeOnActivate: true,
                    computeOnModify: false, unresolved: []
                )
            },
            bindings: [BehaviorBindingSpec("vectorOut", 0)],
            variables: [BehaviorVariableSpec("out", .vector4, 0)]
        )
        transform.update(deltaTime: 0.05)
        guard case let .quad(out) = transform.variable(named: "out") else {
            Issue.record("vectorOut was not written")
            return
        }
        #expect(simd_distance(out, SIMD4(0, 1, 10, 0)) < 1e-5)
    }

    @Test func timeStepIsTheUpdateDelta() {
        let graph = graph(
            running: { set in
                BSGetTimeStepModifier(
                    modifier: BehaviorFixture.modifierHeader("step", bindingSet: set),
                    timeStep: 0, unresolved: []
                )
            },
            bindings: [BehaviorBindingSpec("timeStep", 0)],
            variables: [BehaviorVariableSpec("dt", .real, 0)]
        )
        graph.update(deltaTime: 0.25)
        #expect(graph.variable(named: "dt") == .real(0.25))
    }
}
