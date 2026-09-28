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
import OpenSkyBehavior
import OpenSkyPhysics
import simd

nonisolated public enum LocomotionGraphNames: Sendable {
    // MARK: - Variables (`0_master.hkx` unless noted)

    /// Current gait speed, units per second. Real.
    public static let speed = "Speed"
    /// The damped copy `mt_behavior.hkx` blends its locomotion tree against.
    public static let speedSampled = "SpeedSampled"
    /// Movement direction relative to facing, radians. Real.
    public static let direction = "Direction"
    /// Yaw change over the step, radians. Real.
    public static let turnDelta = "TurnDelta"
    /// Walk and run gait speeds the graph's own blends scale against.
    public static let speedWalk = "SpeedWalk"
    public static let speedRun = "SpeedRun"
    /// Sprinting and sneaking, as bools.
    public static let isSprinting = "IsSprinting"
    public static let isSneaking = "IsSneaking"
    /// The int32 spelling of sneak that both `0_master.hkx` and
    /// `mt_behavior.hkx` declare beside the bool.
    public static let isInSneak = "iIsInSneak"
    /// True while off the ground. Bool.
    public static let inJumpState = "bInJumpState"
    /// Which perspective the instance is running as (issue #190). Declared as
    /// a bool initialised to false by both vanilla `0_master.hkx` files, the
    /// third-person one and the `_1stperson` one, and read by their own
    /// transition conditions. Not in `variables` below: it is seeded once per
    /// instance rather than written every step, and its value differs between
    /// the two graphs where every other input is identical.
    public static let isFirstPerson = "IsFirstPerson"

    /// Every variable the bridge writes, in write order.
    public static let variables = [
        speed, speedSampled, direction, turnDelta,
        isSprinting, isSneaking, isInSneak, inJumpState,
        speedWalk, speedRun
    ]

    // MARK: - Events

    public static let moveStart = "moveStart"
    public static let moveStop = "moveStop"
    public static let sprintStart = "SprintStart"
    public static let sprintStop = "SprintStop"
    public static let sneakStart = "SneakStart"
    public static let sneakStop = "SneakStop"
    /// Takeoff. `JumpFall` follows when the capsule starts descending without
    /// having jumped (walking off a ledge), `JumpLand` when it arrives.
    public static let jumpUp = "JumpUp"
    public static let jumpFall = "JumpFall"
    public static let jumpLand = "JumpLand"
    public static let swimStart = "SwimStart"
    public static let swimStop = "SwimStop"

    /// Every event the bridge can raise.
    public static let events = [
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
nonisolated public struct LocomotionMotionSample: Equatable, Sendable {
    public let gait: LocomotionGait
    public let source: LocomotionMotionSource
    /// Capsule bottom when the change happened.
    public let feetPosition: SIMD3<Float>
    /// Horizontal displacement the step that changed it asked for.
    public let displacement: SIMD2<Float>
    public let isGrounded: Bool
    public let isSwimming: Bool
}

/// What the bridge did, for the `World > Player & Locomotion` readout and for
/// the tests. Value type, snapshot-per-read, like the other panel bridges.
nonisolated public struct LocomotionStatus: Equatable, Sendable {
    /// Whether a behavior graph is attached at all.
    public var graphAvailable = false
    /// Whether the first-person graph is attached beside it (issue #190).
    public var firstPersonGraphAvailable = false
    public var gait: LocomotionGait = .walk
    public var lastPlan: LocomotionStepPlan = .still
    /// Capsule bottom after the last planned step.
    public var feetPosition = SIMD3<Float>()
    public var verticalVelocity: Float = 0
    public var isGrounded = true
    /// Water surface height where the capsule stands, when it is over water.
    public var waterSurfaceHeight: Float?
    /// Graph updates this bridge has driven.
    public var graphUpdates = 0
    /// Names written and raised successfully, and the ones the graph declares
    /// no home for. Sorted for a stable readout.
    public var boundVariables: [String] = []
    public var missingVariables: [String] = []
    public var raisedEvents: [String] = []
    public var missingEvents: [String] = []
    /// Names the graph reported back on the most recent update, newest last.
    public var recentGraphEvents: [String] = []
    /// The same four tallies for the first-person graph, kept apart so a name
    /// the `_1stperson` set spells differently is visible as a first-person
    /// miss rather than blending into the third-person one (issue #190).
    public var firstPersonGraphUpdates = 0
    public var firstPersonBoundVariables: [String] = []
    public var firstPersonMissingVariables: [String] = []
    public var firstPersonRaisedEvents: [String] = []
    public var firstPersonMissingEvents: [String] = []
    public var firstPersonRecentGraphEvents: [String] = []

    /// Where each motion source has carried the capsule so far, world units.
    /// Two running totals rather than one, because "the graph drove the
    /// character" and "the configured gait drove it" are the two answers the
    /// movement-authority rule allows and a readout that summed them could not
    /// tell them apart.
    public var rootMotionDistance: Float = 0
    public var configuredSpeedDistance: Float = 0
    /// Where the resolved gait or the motion source last changed, oldest first.
    public var motionTrace: [LocomotionMotionSample] = []

    /// How many recent graph events are kept for the readout.
    public static let recentEventLimit = 12
    /// How many motion-trace samples are kept.
    public static let motionTraceLimit = 16

    public init(graphAvailable: Bool = false, firstPersonGraphAvailable: Bool = false) {
        self.graphAvailable = graphAvailable
        self.firstPersonGraphAvailable = firstPersonGraphAvailable
    }

    public var isSwimming: Bool {
        lastPlan.isSwimming
    }

    public var motionSource: LocomotionMotionSource {
        lastPlan.motionSource
    }

    public mutating func update(
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
    public mutating func clearMotionTrace() {
        motionTrace = []
        rootMotionDistance = 0
        configuredSpeedDistance = 0
    }

    public mutating func noteGraphUpdate(events: [BehaviorEvent]) {
        graphUpdates += 1
        guard !events.isEmpty else { return }
        recentGraphEvents += events.map { $0.name ?? "event \($0.id)" }
        if recentGraphEvents.count > Self.recentEventLimit {
            recentGraphEvents.removeFirst(recentGraphEvents.count - Self.recentEventLimit)
        }
    }

    public mutating func noteVariableWritten(_ name: String) {
        Self.insert(name, into: &boundVariables)
    }

    public mutating func noteVariableMissing(_ name: String) {
        Self.insert(name, into: &missingVariables)
    }

    public mutating func noteEventRaised(_ name: String) {
        Self.insert(name, into: &raisedEvents)
    }

    public mutating func noteEventMissing(_ name: String) {
        Self.insert(name, into: &missingEvents)
    }

    public mutating func noteFirstPersonGraphUpdate(events: [BehaviorEvent]) {
        firstPersonGraphUpdates += 1
        guard !events.isEmpty else { return }
        firstPersonRecentGraphEvents += events.map { $0.name ?? "event \($0.id)" }
        let overflow = firstPersonRecentGraphEvents.count - Self.recentEventLimit
        if overflow > 0 {
            firstPersonRecentGraphEvents.removeFirst(overflow)
        }
    }

    public mutating func noteFirstPersonVariableWritten(_ name: String) {
        Self.insert(name, into: &firstPersonBoundVariables)
    }

    public mutating func noteFirstPersonVariableMissing(_ name: String) {
        Self.insert(name, into: &firstPersonMissingVariables)
    }

    public mutating func noteFirstPersonEventRaised(_ name: String) {
        Self.insert(name, into: &firstPersonRaisedEvents)
    }

    public mutating func noteFirstPersonEventMissing(_ name: String) {
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
