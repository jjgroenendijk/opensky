// State machines, transitions, and crossfades (issue #330), over synthetic
// graphs built in code — no packfile bytes and nothing from the install.
//
// Every graph below is the same shape: two states, each running a static clip
// that holds bone 1 at a known translation, so the pose says without ambiguity
// which state is showing and how far a crossfade has run.

import Foundation
@testable import opensky
import Testing

/// The pieces one two-state machine is made of, so each test can vary one of
/// them without repeating the wiring.
private struct TwoStateGraph {
    var table = BehaviorObjectTable()
    var root: HKXPointerTarget?

    /// Bone 1 sits at 0 in state "Left" and at 10 in state "Right".
    static var clips: BehaviorClipTable {
        BehaviorFixture.staticClipPair(left: 0, right: 10)
    }

    static let events = ["go", "back", "enteredRight", "leftLeft"]

    /// Builds the machine. `leftTransitions` and `wildcards` are the two places
    /// a transition can be authored.
    init(
        leftTransitions: [BehaviorTransitionSpec] = [],
        rightTransitions: [BehaviorTransitionSpec] = [],
        wildcards: [BehaviorTransitionSpec] = [],
        startStateId: Int = 0,
        startStateMode: Int = 0,
        notifies: Bool = false,
        effect: HKBBlendingTransitionEffect? = nil,
        condition: HKBExpressionCondition? = nil
    ) {
        var conditionTarget: HKXPointerTarget?
        if let condition {
            conditionTarget = table.add(condition, at: 0x080)
        }
        var effectTarget: HKXPointerTarget?
        if let effect {
            effectTarget = table.add(effect, at: 0x090)
        }
        let left = table.add(
            BehaviorFixture.clipGenerator("left", animationName: "left"), at: 0x100
        )
        let right = table.add(
            BehaviorFixture.clipGenerator("right", animationName: "right"), at: 0x110
        )
        let leftArray = addTransitions(
            leftTransitions, at: 0x200, effect: effectTarget, condition: conditionTarget
        )
        let rightArray = addTransitions(
            rightTransitions, at: 0x210, effect: effectTarget, condition: conditionTarget
        )
        let wildcardArray = wildcards.isEmpty
            ? nil
            : addTransitions(
                wildcards, at: 0x220, effect: effectTarget, condition: conditionTarget
            )
        var enter: HKXPointerTarget?
        var exit: HKXPointerTarget?
        if notifies {
            enter = table.add(BehaviorStateMachineFixture.notifyEvents([2]), at: 0x300)
            exit = table.add(BehaviorStateMachineFixture.notifyEvents([3]), at: 0x310)
        }
        let leftState = table.add(
            BehaviorStateMachineFixture.stateInfo(
                BehaviorStateSpec(
                    stateId: 0, name: "Left", generator: left,
                    transitions: leftArray, exitNotifyEvents: exit
                )
            ),
            at: 0x400
        )
        let rightState = table.add(
            BehaviorStateMachineFixture.stateInfo(
                BehaviorStateSpec(
                    stateId: 1, name: "Right", generator: right,
                    transitions: rightArray, enterNotifyEvents: enter
                )
            ),
            at: 0x410
        )
        root = table.add(
            BehaviorStateMachineFixture.machine(
                "machine",
                states: [leftState, rightState],
                startStateId: startStateId,
                startStateMode: startStateMode,
                wildcardTransitions: wildcardArray
            ),
            at: 0x500
        )
    }

    /// Registers one transition array, pointing every spec that asked for them
    /// at the shared effect and condition objects.
    private mutating func addTransitions(
        _ specs: [BehaviorTransitionSpec],
        at offset: Int,
        effect: HKXPointerTarget?,
        condition: HKXPointerTarget?
    ) -> HKXPointerTarget {
        table.add(
            BehaviorStateMachineFixture.transitions(
                Self.wire(specs, effect: effect, condition: condition)
            ),
            at: offset
        )
    }

    /// Points every spec that asked for them at the shared effect and condition.
    private static func wire(
        _ specs: [BehaviorTransitionSpec],
        effect: HKXPointerTarget?,
        condition: HKXPointerTarget?
    ) -> [BehaviorTransitionSpec] {
        specs.map { spec in
            var wired = spec
            if wired.effect == nil {
                wired.effect = effect
            }
            if wired.condition == nil {
                wired.condition = condition
            }
            return wired
        }
    }

    func instance(variables: [BehaviorVariableSpec] = []) -> BehaviorGraphInstance {
        BehaviorFixture.instance(
            root: root,
            table: table,
            data: BehaviorFixture.graphData(variables: variables, events: Self.events),
            clips: Self.clips
        )
    }
}

struct BehaviorStateMachineTests {
    private static let step: Float = 0.1

    // MARK: - Transitions

    @Test func anEventMovesTheMachineToTheNamedState() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1)]
        ).instance()
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 0)
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 10)
        #expect(graph.activeStates.map(\.stateName) == ["Right"])
    }

    @Test func anEventNoTransitionNamesChangesNothing() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1)]
        ).instance()
        graph.raiseEvent(named: "back")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 0)
    }

    @Test func aWildcardTransitionFiresFromAnyState() {
        // Nothing on either state names event 1; only the machine's wildcard
        // array does, and it still moves the machine.
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1)],
            wildcards: [BehaviorTransitionSpec(eventId: 1, toStateId: 0)]
        ).instance()
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 10)
        graph.raiseEvent(named: "back")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 0)
    }

    @Test func aStatesOwnTransitionOutranksAWildcardOfEqualPriority() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(
                eventId: 0,
                toStateId: 0,
                flags: Self.selfFlags
            )],
            wildcards: [BehaviorTransitionSpec(eventId: 0, toStateId: 1)]
        ).instance()
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 0)
    }

    @Test func aHigherPriorityWildcardOutranksAStatesOwnTransition() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(
                eventId: 0,
                toStateId: 0,
                flags: Self.selfFlags
            )],
            wildcards: [BehaviorTransitionSpec(eventId: 0, toStateId: 1, priority: 5)]
        ).instance()
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 10)
    }

    @Test func aTransitionOntoTheCurrentStateIsRefusedWithoutTheSelfFlag() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 0)]
        ).instance()
        graph.raiseEvent(named: "go")
        graph.update(deltaTime: Self.step)
        #expect(graph.activeStates.map(\.stateName) == ["Left"])
    }

    @Test func aDisabledTransitionNeverFires() {
        let flags = BehaviorTransitionFlag.disableCondition | BehaviorTransitionFlag.disabled
        let graph = TwoStateGraph(
            leftTransitions: [
                BehaviorTransitionSpec(eventId: 0, toStateId: 1, flags: flags)
            ]
        ).instance()
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 0)
    }

    // MARK: - Conditions

    @Test func aFalseConditionBlocksTheTransition() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1, flags: 0)],
            condition: BehaviorStateMachineFixture.condition("bReady == 1")
        ).instance(variables: [BehaviorVariableSpec("bReady", .bool, 0)])
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 0)
    }

    @Test func aTrueConditionLetsTheTransitionThrough() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1, flags: 0)],
            condition: BehaviorStateMachineFixture.condition("bReady == 1")
        ).instance(variables: [BehaviorVariableSpec("bReady", .bool, 1)])
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 10)
    }

    @Test func aConditionNamingAnUndeclaredVariableBlocksAndIsTallied() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1, flags: 0)],
            condition: BehaviorStateMachineFixture.condition("bMissing == 1")
        ).instance()
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 0)
        #expect(graph.tally.featureGaps["transitionConditionUnresolved"] == 1)
    }

    // MARK: - Crossfades

    /// The smooth curve is `3t^2 - 2t^3` over `elapsed / duration`, and the
    /// blend is `left + (right - left) * weight` with left at 0 and right at 10.
    /// One 0.1 s step into a 0.4 s crossfade is t = 0.25, weight = 0.15625, so
    /// bone 1 sits at 1.5625.
    @Test func aCrossfadeFollowsTheSmoothCurve() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1)],
            effect: BehaviorStateMachineFixture.blendingEffect(duration: 0.4)
        ).instance()
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 1.5625)
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 5)
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 8.4375)
        // The fourth step reaches the duration, which ends the blend.
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 10)
    }

    @Test func aLinearCrossfadeIsTheFractionItself() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1)],
            effect: BehaviorStateMachineFixture.blendingEffect(
                duration: 0.4, blendCurve: BehaviorBlendCurve.linear
            )
        ).instance()
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 2.5)
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 5)
    }

    @Test func aZeroDurationEffectCutsInstantly() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1)],
            effect: BehaviorStateMachineFixture.blendingEffect(duration: 0)
        ).instance()
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 10)
    }

    @Test func theActiveStateReportsBothEndsOfACrossfade() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1)],
            effect: BehaviorStateMachineFixture.blendingEffect(
                duration: 0.4, blendCurve: BehaviorBlendCurve.linear
            )
        ).instance()
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "go")
        graph.update(deltaTime: Self.step)
        #expect(graph.activeStates.first?.stateName == "Right")
        #expect(graph.activeStates.first?.previousStateName == "Left")
        #expect(graph.activeStates.first?.blendWeight == 0.25)
    }

    // MARK: - Interruption

    /// An event arriving mid-crossfade starts a new one from wherever the
    /// machine has got to, and the abandoned blend is tallied.
    @Test func anEventDuringACrossfadeStartsANewOne() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1)],
            rightTransitions: [BehaviorTransitionSpec(eventId: 1, toStateId: 0)],
            effect: BehaviorStateMachineFixture.blendingEffect(
                duration: 0.4, blendCurve: BehaviorBlendCurve.linear
            )
        ).instance()
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "go")
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "back")
        // Blending back toward Left: one step of the new 0.4 s blend, so the
        // outgoing Right pose still contributes three quarters.
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 7.5)
        #expect(graph.tally.featureGaps["stateMachineTransitionInterrupted"] == 1)
        #expect(graph.activeStates.first?.stateName == "Left")
    }

    @Test func anUninterruptibleTransitionRefusesTheNewEvent() {
        let flags = BehaviorTransitionFlag.disableCondition
            | BehaviorTransitionFlag.uninterruptibleWhileBlending
        let graph = TwoStateGraph(
            leftTransitions: [
                BehaviorTransitionSpec(eventId: 0, toStateId: 1, flags: flags)
            ],
            rightTransitions: [BehaviorTransitionSpec(eventId: 1, toStateId: 0)],
            effect: BehaviorStateMachineFixture.blendingEffect(
                duration: 0.4, blendCurve: BehaviorBlendCurve.linear
            )
        ).instance()
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "go")
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "back")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 5)
        #expect(graph.tally.featureGaps["stateMachineTransitionInterrupted"] == nil)
    }

    // MARK: - Notify events

    @Test func aStateChangeRaisesExitThenEnterEvents() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1)],
            notifies: true
        ).instance()
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "go")
        graph.update(deltaTime: Self.step)
        // Both were raised during the transition update, so they are visible to
        // the next one, exit first.
        let fired = graph.update(deltaTime: Self.step).firedEvents.map(\.name)
        #expect(fired == ["leftLeft", "enteredRight"])
    }

    @Test func startStateModeTwoResumesWhereItStopped() {
        let graph = TwoStateGraph(
            leftTransitions: [BehaviorTransitionSpec(eventId: 0, toStateId: 1)],
            startStateMode: 2
        ).instance()
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 10)
        graph.deactivate()
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 10)
    }

    private static let selfFlags = BehaviorTransitionFlag.disableCondition
        | BehaviorTransitionFlag.allowSelfTransition
}
