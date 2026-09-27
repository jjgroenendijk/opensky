// The graph variable and event names the locomotion bridge binds to
// (issue #188), and the status snapshot that reports what those bindings did.
//
// Every name here is one the vanilla data declares, taken from the census of
// the install's own behavior files (issue #186, docs/formats/hkx-behavior.md)
// rather than from memory: `0_master.hkx` declares 230 variables and 1,217
// events, and a name that is merely plausible resolves to nothing at all. The
// bridge reports a name that does not resolve instead of dropping the write,
// which is how a graph that spells something differently becomes visible.

import Foundation
import simd

nonisolated enum LocomotionGraphNames {
    // MARK: - Variables (`0_master.hkx` unless noted)

    /// Current gait speed, units per second. Real.
    static let speed = "Speed"
    /// The damped copy `mt_behavior.hkx` blends its locomotion tree against.
    static let speedSampled = "SpeedSampled"
    /// Movement direction relative to facing, radians. Real.
    static let direction = "Direction"
    /// Yaw change over the step, radians. Real.
    static let turnDelta = "TurnDelta"
    /// Walk and run gait speeds the graph's own blends scale against.
    static let speedWalk = "SpeedWalk"
    static let speedRun = "SpeedRun"
    /// Sprinting and sneaking, as bools.
    static let isSprinting = "IsSprinting"
    static let isSneaking = "IsSneaking"
    /// The int32 spelling of sneak that both `0_master.hkx` and
    /// `mt_behavior.hkx` declare beside the bool.
    static let isInSneak = "iIsInSneak"
    /// True while off the ground. Bool.
    static let inJumpState = "bInJumpState"
    /// Which perspective the instance is running as (issue #190). Declared as
    /// a bool initialised to false by both vanilla `0_master.hkx` files, the
    /// third-person one and the `_1stperson` one, and read by their own
    /// transition conditions. Not in `variables` below: it is seeded once per
    /// instance rather than written every step, and its value differs between
    /// the two graphs where every other input is identical.
    static let isFirstPerson = "IsFirstPerson"

    /// Every variable the bridge writes, in write order.
    static let variables = [
        speed, speedSampled, direction, turnDelta,
        isSprinting, isSneaking, isInSneak, inJumpState,
        speedWalk, speedRun
    ]

    // MARK: - Events

    static let moveStart = "moveStart"
    static let moveStop = "moveStop"
    static let sprintStart = "SprintStart"
    static let sprintStop = "SprintStop"
    static let sneakStart = "SneakStart"
    static let sneakStop = "SneakStop"
    /// Takeoff. `JumpFall` follows when the capsule starts descending without
    /// having jumped (walking off a ledge), `JumpLand` when it arrives.
    static let jumpUp = "JumpUp"
    static let jumpFall = "JumpFall"
    static let jumpLand = "JumpLand"
    static let swimStart = "SwimStart"
    static let swimStop = "SwimStop"

    /// Every event the bridge can raise.
    static let events = [
        moveStart, moveStop, sprintStart, sprintStop, sneakStart, sneakStop,
        jumpUp, jumpFall, jumpLand, swimStart, swimStop
    ]
}

/// One entry of the root-motion trace: the step at which the resolved gait or
/// the motion source last changed, and where the capsule was when it did
/// (issue #191).
///
/// The trace records changes rather than steps. A step is 1/120 s, so keeping
/// one sample per step would be twelve hundredths of a second of history and
/// would allocate on every fixed step; keeping one sample per change covers a
/// whole route and costs nothing while the player keeps walking.
nonisolated struct LocomotionMotionSample: Equatable, Sendable {
    let gait: LocomotionGait
    let source: LocomotionMotionSource
    /// Capsule bottom when the change happened.
    let feetPosition: SIMD3<Float>
    /// Horizontal displacement the step that changed it asked for.
    let displacement: SIMD2<Float>
    let isGrounded: Bool
    let isSwimming: Bool
}

/// What the bridge did, for the `World > Player & Locomotion` readout and for
/// the tests. Value type, snapshot-per-read, like the other panel bridges.
nonisolated struct LocomotionStatus: Equatable, Sendable {
    /// Whether a behavior graph is attached at all.
    var graphAvailable = false
    /// Whether the first-person graph is attached beside it (issue #190).
    var firstPersonGraphAvailable = false
    var gait: LocomotionGait = .walk
    var lastPlan: LocomotionStepPlan = .still
    /// Capsule bottom after the last planned step.
    var feetPosition = SIMD3<Float>()
    var verticalVelocity: Float = 0
    var isGrounded = true
    /// Water surface height where the capsule stands, when it is over water.
    var waterSurfaceHeight: Float?
    /// Graph updates this bridge has driven.
    var graphUpdates = 0
    /// Names written and raised successfully, and the ones the graph declares
    /// no home for. Sorted for a stable readout.
    var boundVariables: [String] = []
    var missingVariables: [String] = []
    var raisedEvents: [String] = []
    var missingEvents: [String] = []
    /// Names the graph reported back on the most recent update, newest last.
    var recentGraphEvents: [String] = []
    /// The same four tallies for the first-person graph, kept apart so a name
    /// the `_1stperson` set spells differently is visible as a first-person
    /// miss rather than blending into the third-person one (issue #190).
    var firstPersonGraphUpdates = 0
    var firstPersonBoundVariables: [String] = []
    var firstPersonMissingVariables: [String] = []
    var firstPersonRaisedEvents: [String] = []
    var firstPersonMissingEvents: [String] = []
    var firstPersonRecentGraphEvents: [String] = []

    /// Where each motion source has carried the capsule so far, world units.
    /// Two running totals rather than one, because "the graph drove the
    /// character" and "the configured gait drove it" are the two answers the
    /// movement-authority rule allows and a readout that summed them could not
    /// tell them apart.
    var rootMotionDistance: Float = 0
    var configuredSpeedDistance: Float = 0
    /// Where the resolved gait or the motion source last changed, oldest first.
    var motionTrace: [LocomotionMotionSample] = []

    /// How many recent graph events are kept for the readout.
    static let recentEventLimit = 12
    /// How many motion-trace samples are kept.
    static let motionTraceLimit = 16

    init(graphAvailable: Bool = false, firstPersonGraphAvailable: Bool = false) {
        self.graphAvailable = graphAvailable
        self.firstPersonGraphAvailable = firstPersonGraphAvailable
    }

    var isSwimming: Bool {
        lastPlan.isSwimming
    }

    var motionSource: LocomotionMotionSource {
        lastPlan.motionSource
    }

    mutating func update(
        gait: LocomotionGait,
        plan: LocomotionStepPlan,
        state: LocomotionStepState,
        waterSurface: Float?
    ) {
        let changed = gait != self.gait || plan.motionSource != lastPlan.motionSource
        self.gait = gait
        lastPlan = plan
        feetPosition = state.feetPosition
        verticalVelocity = state.verticalVelocity
        isGrounded = state.isGrounded
        waterSurfaceHeight = waterSurface
        recordMotion(plan: plan, changed: changed || motionTrace.isEmpty)
    }

    /// Adds the step's travel to its source's total and, when the step changed
    /// what is driving the character, appends a trace sample.
    private mutating func recordMotion(plan: LocomotionStepPlan, changed: Bool) {
        let travelled = simd_length(plan.horizontalDisplacement)
        switch plan.motionSource {
        case .rootMotion: rootMotionDistance += travelled
        case .configuredSpeed: configuredSpeedDistance += travelled
        case .idle: break
        }
        guard changed else { return }
        motionTrace.append(LocomotionMotionSample(
            gait: gait,
            source: plan.motionSource,
            feetPosition: feetPosition,
            displacement: plan.horizontalDisplacement,
            isGrounded: isGrounded,
            isSwimming: plan.isSwimming
        ))
        if motionTrace.count > Self.motionTraceLimit {
            motionTrace.removeFirst(motionTrace.count - Self.motionTraceLimit)
        }
    }

    /// Empties the trace and both totals without disturbing anything the
    /// player can feel, which is what the panel's own clear control does.
    mutating func clearMotionTrace() {
        motionTrace = []
        rootMotionDistance = 0
        configuredSpeedDistance = 0
    }

    mutating func noteGraphUpdate(events: [BehaviorEvent]) {
        graphUpdates += 1
        guard !events.isEmpty else { return }
        recentGraphEvents += events.map { $0.name ?? "event \($0.id)" }
        if recentGraphEvents.count > Self.recentEventLimit {
            recentGraphEvents.removeFirst(recentGraphEvents.count - Self.recentEventLimit)
        }
    }

    mutating func noteVariableWritten(_ name: String) {
        Self.insert(name, into: &boundVariables)
    }

    mutating func noteVariableMissing(_ name: String) {
        Self.insert(name, into: &missingVariables)
    }

    mutating func noteEventRaised(_ name: String) {
        Self.insert(name, into: &raisedEvents)
    }

    mutating func noteEventMissing(_ name: String) {
        Self.insert(name, into: &missingEvents)
    }

    mutating func noteFirstPersonGraphUpdate(events: [BehaviorEvent]) {
        firstPersonGraphUpdates += 1
        guard !events.isEmpty else { return }
        firstPersonRecentGraphEvents += events.map { $0.name ?? "event \($0.id)" }
        let overflow = firstPersonRecentGraphEvents.count - Self.recentEventLimit
        if overflow > 0 {
            firstPersonRecentGraphEvents.removeFirst(overflow)
        }
    }

    mutating func noteFirstPersonVariableWritten(_ name: String) {
        Self.insert(name, into: &firstPersonBoundVariables)
    }

    mutating func noteFirstPersonVariableMissing(_ name: String) {
        Self.insert(name, into: &firstPersonMissingVariables)
    }

    mutating func noteFirstPersonEventRaised(_ name: String) {
        Self.insert(name, into: &firstPersonRaisedEvents)
    }

    mutating func noteFirstPersonEventMissing(_ name: String) {
        Self.insert(name, into: &firstPersonMissingEvents)
    }

    private static func insert(_ name: String, into names: inout [String]) {
        guard let index = names.firstIndex(where: { $0 >= name }) else {
            names.append(name)
            return
        }
        guard names[index] != name else { return }
        names.insert(name, at: index)
    }
}
