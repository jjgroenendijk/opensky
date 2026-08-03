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

/// What the bridge did, for the `World > Player & Locomotion` readout and for
/// the tests. Value type, snapshot-per-read, like the other panel bridges.
nonisolated struct LocomotionStatus: Equatable, Sendable {
    /// Whether a behavior graph is attached at all.
    var graphAvailable = false
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

    /// How many recent graph events are kept for the readout.
    static let recentEventLimit = 12

    init(graphAvailable: Bool = false) {
        self.graphAvailable = graphAvailable
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
        self.gait = gait
        lastPlan = plan
        feetPosition = state.feetPosition
        verticalVelocity = state.verticalVelocity
        isGrounded = state.isGrounded
        waterSurfaceHeight = waterSurface
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

    private static func insert(_ name: String, into names: inout [String]) {
        guard let index = names.firstIndex(where: { $0 >= name }) else {
            names.append(name)
            return
        }
        guard names[index] != name else { return }
        names.insert(name, at: index)
    }
}
