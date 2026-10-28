// The rules of the per-actor behaviour graphs: how often a graph steps at a distance,
// which locomotion events a change of motion raises, and what each step writes.
// Pure; `ActorGraphCoordinator` is the shell. See docs/engine/actor-graphs.md.

import Foundation
import OpenSkyBehavior
import simd

/// How far from the camera an actor's graph steps every frame, at a reduced rate, or
/// not at all. A graph that does not step keeps its last pose.
nonisolated public struct ActorGraphCutoff: Equatable, Sendable {
    /// Seconds between steps past `fullRateDistance`: 15 steps per second.
    public static let reducedStepInterval: Float = 1.0 / 15
    /// Seconds between steps in the outer half of `fullRateDistance`: 30 steps per second.
    public static let nearStepInterval: Float = 1.0 / 30
    public static let standard = ActorGraphCutoff(fullRateDistance: 2048, maximumDistance: 6144)

    public var fullRateDistance: Float
    public var maximumDistance: Float

    public init(fullRateDistance: Float, maximumDistance: Float) {
        self.fullRateDistance = max(0, fullRateDistance)
        self.maximumDistance = max(self.fullRateDistance, maximumDistance)
    }

    /// Zero steps every frame. Nil does not step.
    public func stepInterval(atDistance distance: Float) -> Float? {
        if distance <= fullRateDistance * 0.5 {
            return 0
        }
        if distance <= fullRateDistance {
            return Self.nearStepInterval
        }
        return distance <= maximumDistance ? Self.reducedStepInterval : nil
    }
}

/// What an actor's movement drive does, as the graph's locomotion inputs see it.
nonisolated public struct ActorGraphMotion: Equatable, Sendable {
    public var isMoving: Bool
    public var isSprinting: Bool
    public var isSneaking: Bool
    /// The horse graphs' `iCombatStance`: the actor, or its rider, has a weapon out.
    public var isInCombatStance: Bool

    public static let still = ActorGraphMotion()

    public init(
        isMoving: Bool = false,
        isSprinting: Bool = false, isSneaking: Bool = false, isInCombatStance: Bool = false
    ) {
        self.isMoving = isMoving
        self.isSprinting = isSprinting
        self.isSneaking = isSneaking
        self.isInCombatStance = isInCombatStance
    }
}

/// An NPC's measured speed, smoothed, and whether its walk has stalled. A mover blocked
/// in place still asks to walk; its graph is told it stopped, so it does not walk on the spot.
nonisolated public struct ActorGraphGait: Equatable, Sendable {
    /// Seconds over which the measured speed settles, so a frame without a move does
    /// not drop `Speed` to zero.
    public static let smoothingTime: Float = 0.2
    /// Below this many units per second a driven actor is not getting anywhere.
    public static let stallSpeed: Float = 10
    /// How long a driven actor stays below `stallSpeed` before its graph stops.
    public static let stallDelay: Float = 0.5
    /// Faster than any gait; a teleport would read as a run otherwise.
    public static let maximumSpeed: Float = 1000

    public private(set) var speed: Float = 0
    public private(set) var stalledFor: Float = 0

    public init() {}

    public var isStalled: Bool {
        stalledFor >= Self.stallDelay
    }

    public mutating func sample(_ measured: Float, seconds: Float, isDriven: Bool) {
        guard seconds > 0 else { return }
        let clamped = measured.isFinite ? min(max(measured, 0), Self.maximumSpeed) : 0
        speed += (clamped - speed) * (1 - exp(-seconds / Self.smoothingTime))
        stalledFor = isDriven && speed < Self.stallSpeed ? stalledFor + seconds : 0
    }

    /// The drive's motion as the graph should hear it.
    public func shown(_ drive: ActorGraphMotion) -> ActorGraphMotion {
        guard isStalled else { return drive }
        var motion = drive
        motion.isMoving = false
        motion.isSprinting = false
        return motion
    }
}

/// Graph names an actor's step writes and raises. The human graph declares all of them;
/// a creature graph declares a subset, and a missing name is skipped.
nonisolated public enum ActorGraphNames {
    public static let speed = "Speed"
    public static let speedSampled = "SpeedSampled"
    public static let direction = "Direction"
    public static let turnDelta = "TurnDelta"
    public static let isSprinting = "IsSprinting"
    public static let isSneaking = "IsSneaking"
    public static let isInSneak = "iIsInSneak"
    public static let isPlayer = "IsPlayer"
    public static let isPlayerInt = "iIsPlayer"
    public static let isNPC = "IsNPC"
    public static let timeDelta = "TimeDelta"
    /// The actor's weight as 0 to 1. `mt_behavior.hkx` turns it into the body-weight layer
    /// weights `bodyMorphWeight` and `bodyMorphMuscular` with an expression. Real.
    public static let weaponAdjust = "weapAdj"
    public static let bodyMorphWeight = "bodyMorphWeight"
    public static let bodyMorphMuscular = "bodyMorphMuscular"

    public static let moveStart = "moveStart"
    public static let moveStop = "moveStop"
    public static let sprintStart = "SprintStart"
    public static let sprintStop = "SprintStop"
    public static let sneakStart = "SneakStart"
    public static let sneakStop = "SneakStop"

    /// The start state of `StandingIdleBehavior` in both horse graphs: 0 is
    /// `NonCombatIdleState`, 1 is `CombatIdleState` (docs/engine/riding.md). Int32.
    public static let combatStance = "iCombatStance"
    public static let combatStanceStart = "combatStanceStart"
    public static let combatStanceStop = "combatStanceStop"

    /// The events of the idles `IdleDrunkStart` and `IdleDrunkStop`; `mt_behavior.hkx`
    /// enters and leaves `MT_Drunk` on them.
    public static let drunkStart = "DrunkStart"
    public static let drunkStop = "DrunkStop"
    public static let state = "iState"
    /// The `iState` constants a drunk and a sober actor report.
    public static let drunkState = "iState_NPCDrunk"
    public static let defaultState = "iState_NPCDefault"
}

/// What one actor's graph is fed in one step.
nonisolated public struct ActorGraphStepInput: Equatable, Sendable {
    public var motion: ActorGraphMotion
    /// Horizontal travel since the last step, world units per second.
    public var speed: Float
    /// Yaw change since the last step, radians.
    public var turnDelta: Float
    public var deltaTime: Float
    /// The NPC weight, 0 (thin) to 100 (heavy).
    public var weight: Float = 50

    public init(motion: ActorGraphMotion, speed: Float, turnDelta: Float, deltaTime: Float) {
        self.motion = motion
        self.speed = speed
        self.turnDelta = turnDelta
        self.deltaTime = deltaTime
    }
}

nonisolated public enum ActorGraphCore {
    /// The events a drive change raises, move before sprint before sneak.
    public static func events(from old: ActorGraphMotion, to new: ActorGraphMotion) -> [String] {
        typealias Names = ActorGraphNames
        var events: [String] = []
        if old.isMoving != new.isMoving {
            events.append(new.isMoving ? Names.moveStart : Names.moveStop)
        }
        if old.isSprinting != new.isSprinting {
            events.append(new.isSprinting ? Names.sprintStart : Names.sprintStop)
        }
        if old.isSneaking != new.isSneaking {
            events.append(new.isSneaking ? Names.sneakStart : Names.sneakStop)
        }
        if old.isInCombatStance != new.isInCombatStance {
            events.append(new.isInCombatStance ? Names.combatStanceStart : Names.combatStanceStop)
        }
        return events
    }

    /// The variables one step writes, in write order. An NPC walks where it faces, so
    /// `Direction` stays 0. `weapAdj` comes last.
    public static func variables(_ input: ActorGraphStepInput)
        -> [(name: String, value: BehaviorVariableValue)]
    {
        typealias Names = ActorGraphNames
        let speed = input.motion.isMoving ? input.speed : 0
        return [
            (Names.speed, .real(speed)),
            (Names.speedSampled, .real(speed)),
            (Names.direction, .real(0)),
            (Names.turnDelta, .real(input.turnDelta)),
            (Names.isSprinting, .bool(input.motion.isSprinting)),
            (Names.isSneaking, .bool(input.motion.isSneaking)),
            (Names.isInSneak, .int(input.motion.isSneaking ? 1 : 0)),
            (Names.isPlayer, .bool(false)),
            (Names.isPlayerInt, .int(0)),
            (Names.isNPC, .bool(true)),
            (Names.combatStance, .int(input.motion.isInCombatStance ? 1 : 0)),
            (Names.timeDelta, .real(input.deltaTime)),
            (Names.weaponAdjust, .real(weaponAdjust(weight: input.weight)))
        ]
    }

    /// The `iState` constant to write after the graph's drunk tag changed, else nil. Only
    /// the change is written, so an NPC keeps any other `iState` its graph holds.
    public static func stateConstant(wasDrunk: Bool, isDrunk: Bool) -> String? {
        guard wasDrunk != isDrunk else { return nil }
        return isDrunk ? ActorGraphNames.drunkState : ActorGraphNames.defaultState
    }

    /// `weapAdj` for an actor weight from 0 (thin) to 100 (heavy)
    /// (docs/engine/behavior-clips.md#body-weight-layer).
    public static func weaponAdjust(weight: Float) -> Float {
        weight.isFinite ? min(max(weight / 100, 0), 1) : 0.5
    }

    /// Horizontal speed between two feet positions, or 0 without a time step.
    public static func speed(from old: SIMD3<Float>, to new: SIMD3<Float>, seconds: Float)
        -> Float
    {
        guard seconds > 0 else { return 0 }
        return simd_length(SIMD2(new.x - old.x, new.y - old.y)) / seconds
    }

    /// The shortest turn from `old` to `new`, in (-pi, pi].
    public static func turnDelta(from old: Float, to new: Float) -> Float {
        let turn = remainder(new - old, 2 * Float.pi)
        return turn == -Float.pi ? Float.pi : turn
    }

    /// The archive path of a race's behaviour graph project. The record names it
    /// relative to `Data\meshes`, such as `Actors\Canine\WolfProject.hkx`.
    public static func projectPath(modelPath: String) -> String {
        "meshes\\" + modelPath.replacingOccurrences(of: "/", with: "\\").lowercased()
    }

    /// A placement's Z rotation turns clockwise seen from above, and Havok's model
    /// forward is +Y, so the model turns by the negated angle.
    public static func worldRotation(placementRotationZ angle: Float) -> simd_quatf {
        simd_quatf(angle: -angle, axis: SIMD3(0, 0, 1))
    }
}
