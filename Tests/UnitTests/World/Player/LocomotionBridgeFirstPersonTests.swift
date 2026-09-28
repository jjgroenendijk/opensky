// The bridge driving two graphs at once (issue #190): identical inputs, one
// perspective variable that differs, and two instances that cannot perturb
// each other. Synthetic graphs only — no install.

@testable import opensky
import simd
import Testing

struct LocomotionBridgeFirstPersonTests {
    /// A graph declaring every name the bridge writes plus `IsFirstPerson`, so
    /// nothing here fails for the uninteresting reason of a missing name.
    private static func graph() -> BehaviorGraphInstance {
        var variables = LocomotionGraphNames.variables.map {
            BehaviorVariableSpec($0, .real, 0)
        }
        variables.append(BehaviorVariableSpec(LocomotionGraphNames.isFirstPerson, .bool, 0))
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("idle", animationName: "idle"), at: 0x10
        )
        return BehaviorFixture.instance(
            root: root,
            table: table,
            data: BehaviorFixture.graphData(
                variables: variables, events: LocomotionGraphNames.events
            )
        )
    }

    /// A bridge and both instances it drives, so a test can assert on either
    /// side by name.
    private struct Pair {
        let bridge: LocomotionBridge
        let third: BehaviorGraphInstance
        let first: BehaviorGraphInstance
    }

    private static func bridge() -> Pair {
        let third = graph()
        let first = graph()
        let bridge = LocomotionBridge(configuration: .synthetic, graph: third)
        bridge.attachFirstPerson(graph: first)
        return Pair(bridge: bridge, third: third, first: first)
    }

    private static func state(dt: Float = WalkController.fixedTimeStep) -> LocomotionStepState {
        LocomotionStepState(
            feetPosition: .zero, verticalVelocity: 0, isGrounded: true, yaw: 0, dt: dt
        )
    }

    // MARK: - Perspective

    /// The one input that differs, and the whole reason two instances exist.
    @Test
    func onlyTheFirstPersonGraphIsToldItIsFirstPerson() {
        let pair = Self.bridge()
        let third = pair.third
        let first = pair.first
        #expect(
            third.variable(named: LocomotionGraphNames.isFirstPerson)?.boolValue == false
        )
        #expect(
            first.variable(named: LocomotionGraphNames.isFirstPerson)?.boolValue == true
        )
    }

    /// A reset re-seeds it: attaching, teleporting, or entering walk mode must
    /// not leave a graph unsure which perspective it is.
    @Test
    func resetReseedsThePerspective() {
        let pair = Self.bridge()
        let bridge = pair.bridge
        let first = pair.first
        _ = first.setVariable(.bool(false), named: LocomotionGraphNames.isFirstPerson)
        bridge.reset()
        #expect(
            first.variable(named: LocomotionGraphNames.isFirstPerson)?.boolValue == true
        )
    }

    // MARK: - Identical inputs

    /// Every variable the bridge writes reaches both graphs with the same
    /// value, and every edge event reaches both.
    @Test
    func bothGraphsSeeTheSameStateAndEvents() {
        let pair = Self.bridge()
        let bridge = pair.bridge
        let third = pair.third
        let first = pair.first
        bridge.intent = LocomotionIntent(moveForward: 1, sprint: true)
        _ = bridge.plan(Self.state())
        for name in LocomotionGraphNames.variables {
            #expect(third.variable(named: name) == first.variable(named: name), "\(name)")
        }
        #expect(bridge.status.boundVariables == bridge.status.firstPersonBoundVariables)
        #expect(bridge.status.raisedEvents == bridge.status.firstPersonRaisedEvents)
        #expect(bridge.status.raisedEvents.contains(LocomotionGraphNames.moveStart))
        #expect(bridge.status.raisedEvents.contains(LocomotionGraphNames.sprintStart))
    }

    /// Both are stepped exactly once per fixed step, and a zero-length step
    /// steps neither.
    @Test
    func bothGraphsStepOncePerFixedStep() {
        let pair = Self.bridge()
        let bridge = pair.bridge
        for _ in 0 ..< 5 {
            _ = bridge.plan(Self.state())
        }
        #expect(bridge.status.graphUpdates == 5)
        #expect(bridge.status.firstPersonGraphUpdates == 5)
        _ = bridge.plan(Self.state(dt: 0))
        #expect(bridge.status.graphUpdates == 5)
        #expect(bridge.status.firstPersonGraphUpdates == 5)
    }

    /// A miss is reported against the graph that missed it, not folded into
    /// the other's tally.
    @Test
    func aFirstPersonMissIsReportedSeparately() {
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("idle", animationName: "idle"), at: 0x10
        )
        let sparse = BehaviorFixture.instance(
            root: root, table: table, data: BehaviorFixture.graphData()
        )
        let bridge = LocomotionBridge(configuration: .synthetic, graph: Self.graph())
        bridge.attachFirstPerson(graph: sparse)
        _ = bridge.plan(Self.state())
        #expect(bridge.status.missingVariables.isEmpty)
        #expect(
            bridge.status.firstPersonMissingVariables == LocomotionGraphNames.variables.sorted()
        )
    }

    // MARK: - Independence

    /// The acceptance criterion: stepping the first-person graph never
    /// perturbs the third-person instance's poses or events.
    @Test
    func steppingOneGraphLeavesTheOtherUntouched() {
        let solo = LocomotionBridge(configuration: .synthetic, graph: Self.graph())
        solo.intent = LocomotionIntent(moveForward: 1)
        for _ in 0 ..< 10 {
            _ = solo.plan(Self.state())
        }
        let paired = LocomotionBridge(configuration: .synthetic, graph: Self.graph())
        paired.attachFirstPerson(graph: Self.graph())
        paired.intent = LocomotionIntent(moveForward: 1)
        for _ in 0 ..< 10 {
            _ = paired.plan(Self.state())
        }
        #expect(solo.pose.bones == paired.pose.bones)
        #expect(solo.status.recentGraphEvents == paired.status.recentGraphEvents)
        #expect(solo.status.lastPlan == paired.status.lastPlan)
    }

    /// The two poses live in two buffers. A shared one would hand the arms the
    /// body's bones, and both would look right until the rigs differed.
    @Test
    func thePosesAreSeparateBuffers() {
        let pair = Self.bridge()
        let bridge = pair.bridge
        _ = bridge.plan(Self.state())
        #expect(bridge.pose.revision > 0)
        #expect(bridge.firstPersonPose.revision > 0)
        bridge.pose.clear()
        #expect(bridge.pose.bones.isEmpty)
        #expect(!bridge.firstPersonPose.bones.isEmpty)
    }

    /// The first-person graph is never allowed to move the character: the plan
    /// a bridge with one attached produces is the plan it produces without.
    @Test
    func theFirstPersonGraphCannotMoveTheCapsule() {
        let solo = LocomotionBridge(configuration: .synthetic, graph: Self.graph())
        solo.intent = LocomotionIntent(moveForward: 1)
        let alone = solo.plan(Self.state())

        let paired = LocomotionBridge(configuration: .synthetic, graph: Self.graph())
        paired.attachFirstPerson(graph: Self.graph())
        paired.intent = LocomotionIntent(moveForward: 1)
        #expect(paired.plan(Self.state()) == alone)
    }

    /// A bridge with no first-person graph is a supported configuration, not a
    /// degraded one.
    @Test
    func noFirstPersonGraphIsSupported() {
        let bridge = LocomotionBridge(configuration: .synthetic, graph: Self.graph())
        bridge.intent = LocomotionIntent(moveForward: 1)
        _ = bridge.plan(Self.state())
        #expect(!bridge.status.firstPersonGraphAvailable)
        #expect(bridge.status.firstPersonGraphUpdates == 0)
        #expect(bridge.status.firstPersonMissingVariables.isEmpty)
        #expect(bridge.firstPersonPose.bones.isEmpty)
    }
}
