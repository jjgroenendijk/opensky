// Transitions in flight: the `hkbStateMachineTransitionInfo` flag map, the
// `hkbBlendingTransitionEffect` crossfade, and its blend curve. The flag map
// comes from open sources (`docs/decisions/havok-behavior-scope.md`) and was
// checked against the install (`docs/engine/behavior-state-machines.md`). Bits
// the player graph never sets are named but not acted on.

import Foundation
public import OpenSkyFormatsAnimation

/// `hkbStateMachineTransitionInfo::TransitionFlags`, as far as the vanilla
/// player graph exercises them.
nonisolated public enum BehaviorTransitionFlag: Sendable {
    /// The transition may only trigger inside `m_triggerInterval`.
    public static let useTriggerInterval = 0x1
    /// The transition may only start inside `m_initiateInterval`.
    public static let useInitiateInterval = 0x2
    /// No other transition may replace this one while its destination plays.
    public static let uninterruptibleWhilePlaying = 0x4
    /// No other transition may replace this one while its state change waits.
    public static let uninterruptibleWhileDelayed = 0x8
    /// The state change waits for the blend to finish.
    public static let delayStateChange = 0x10
    /// The transition is authored but switched off.
    public static let disabled = 0x20
    /// `m_returnToPreviousStateEventId` may not return through this transition.
    public static let disallowReturnToPreviousState = 0x40
    /// The random transition event may not pick this transition.
    public static let disallowRandomTransition = 0x80
    /// `m_condition` is not evaluated. Set by the exporter on every transition
    /// that carries no condition object.
    public static let disableCondition = 0x100
    /// A transition whose destination is the state it starts from may fire.
    public static let allowSelfTransition = 0x200
    /// The transition lives in a wildcard array and applies from any state.
    public static let globalWildcard = 0x400
    public static let localWildcard = 0x800
    /// `m_fromNestedStateId` / `m_toNestedStateId` name a state of a nested
    /// machine rather than of this one.
    public static let fromNestedStateIsValid = 0x1000
    public static let toNestedStateIsValid = 0x2000
}

/// `hkbBlendingTransitionEffect::FlagBits`. Only the sync bit is acted on; the others
/// describe root motion across the blend, which the locomotion bridge owns.
nonisolated public enum BehaviorTransitionEffectFlag: Sendable {
    public static let ignoreFromGenerator = 0x1
    /// Align the incoming generator's clip time with the outgoing one's.
    public static let sync = 0x2
}

/// `hkbBlendCurveUtils::BlendCurve`, from a clean-room read of the game
/// (docs/engine/behavior-clips.md#blending).
nonisolated public enum BehaviorBlendCurve: Sendable {
    public static let smooth = 0
    public static let linear = 1
    public static let linearToSmooth = 2
    public static let smoothToLinear = 3

    /// The destination's share of the blend at `fraction` of the way through. An
    /// unknown curve falls back to smooth and is tallied.
    public static func weight(_ fraction: Float, curve: Int) -> Float {
        let time = fraction.isFinite ? min(max(fraction, 0), 1) : 1
        let square = time * time
        switch curve {
        case linear: return time
        case linearToSmooth: return time + square - square * time
        case smoothToLinear: return 2 * square - square * time
        default: return square * (3 - 2 * time)
        }
    }

    public static func isKnown(_ curve: Int) -> Bool {
        (smooth ... smoothToLinear).contains(curve)
    }
}

/// One crossfade in progress inside a state machine. Built when the transition
/// starts and stepped by every update until it is finished.
nonisolated public struct BehaviorTransition: Equatable, Sendable {
    /// The state the machine is blending out of. The machine's own
    /// `currentStateId` is already the destination: the state change happens
    /// when the transition starts and the effect only fades the old pose.
    public var fromStateId: Int
    public var elapsed: Float
    public var duration: Float
    public var blendCurve: Int
    /// `hkbBlendingTransitionEffect::m_flags`.
    public var effectFlags: Int
    /// `hkbStateMachineTransitionInfo::m_flags` of the transition that started
    /// this blend, so the interruption rules can read them back.
    public var transitionFlags: Int

    /// How much of the destination pose is showing.
    public var weight: Float {
        guard duration > 0 else { return 1 }
        return BehaviorBlendCurve.weight(elapsed / duration, curve: blendCurve)
    }

    public var isFinished: Bool {
        !(elapsed < duration)
    }

    public var ignoresFromGenerator: Bool {
        effectFlags & BehaviorTransitionEffectFlag.ignoreFromGenerator != 0
    }

    public var synchronizes: Bool {
        effectFlags & BehaviorTransitionEffectFlag.sync != 0
    }

    /// The transition's `m_priority`: a new one needs at least as much to replace it.
    public var priority = 0
    /// The transition that was running when this one started. It keeps running as this
    /// one's source pose until it ends.
    public var interrupted: [BehaviorTransition] = []
    /// With `FLAG_DELAY_STATE_CHANGE`, the destination. The machine stays in
    /// `fromStateId` until the blend ends.
    public var delayedStateId: Int?

    public var isUninterruptibleWhilePlaying: Bool {
        transitionFlags & BehaviorTransitionFlag.uninterruptibleWhilePlaying != 0
    }

    /// True when this transition keeps a new one with `info` from replacing it.
    public func refuses(_ info: HKBStateMachineTransitionInfo) -> Bool {
        if isUninterruptibleWhilePlaying || info.priority < priority {
            return true
        }
        let delayedLock = transitionFlags & BehaviorTransitionFlag.uninterruptibleWhileDelayed
        return delayedStateId != nil && delayedLock != 0
    }

    /// Steps this transition and every one it interrupted; a finished inner one ends.
    public mutating func advance(by deltaTime: Float) {
        elapsed += max(deltaTime, 0)
        interrupted = interrupted.compactMap { inner in
            var inner = inner
            inner.advance(by: deltaTime)
            return inner.isFinished ? nil : inner
        }
    }

    /// Keeps at most `limit` transitions in the chain; the oldest end first.
    public mutating func trim(to limit: Int) {
        guard limit > 1 else {
            interrupted = []
            return
        }
        interrupted = interrupted.map { inner in
            var inner = inner
            inner.trim(to: limit - 1)
            return inner
        }
    }
}

/// The runtime state of one `hkbStateMachine`. Kept apart from
/// `BehaviorNodeState` because it outlives deactivation: `m_startStateMode` 2
/// re-enters the state that was current when the machine stopped, and 121 of
/// the 1,963 machines in the vanilla player graph are authored that way.
nonisolated public struct BehaviorMachineState: Equatable, Sendable {
    public var currentStateId = -1
    /// The state before the current one, for `m_returnToPreviousStateEventId`.
    public var previousStateId = -1
    /// True between entering the start state and deactivation.
    public var isEntered = false
    public var transition: BehaviorTransition?
}

/// What one machine is doing now, in names rather than ids. Published per update, so a
/// test or a state read can check a state path without reaching into the evaluator.
nonisolated public struct BehaviorActiveState: Equatable, Sendable {
    public let machineName: String?
    public let stateId: Int
    public let stateName: String?
    /// The state being blended out of, while a crossfade is running.
    public let previousStateName: String?
    /// The destination's share of the blend: 1 when nothing is in flight.
    public let blendWeight: Float
}
