// Transitions in flight: the `hkbStateMachineTransitionInfo` flag map, the
// `hkbBlendingTransitionEffect` crossfade, and its blend curve. The flag map
// comes from open sources (`docs/decisions/havok-behavior-scope.md`) and was
// checked against the install (`docs/engine/behavior-state-machines.md`). Bits
// the player graph never sets are named but not acted on.

import Foundation

/// `hkbStateMachineTransitionInfo::TransitionFlags`, as far as the vanilla
/// player graph exercises them.
nonisolated public enum BehaviorTransitionFlag: Sendable {
    /// The transition may only trigger inside `m_triggerInterval`.
    public static let useTriggerInterval = 0x1
    /// The transition may only start inside `m_initiateInterval`.
    public static let useInitiateInterval = 0x2
    /// No other transition may replace this one while its destination plays.
    public static let uninterruptibleWhilePlaying = 0x4
    /// No other transition may replace this one while it is still blending.
    public static let uninterruptibleWhileBlending = 0x8
    /// The state change waits for the blend to finish.
    public static let delayStateChange = 0x10
    /// The transition is authored but switched off.
    public static let disabled = 0x20
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

/// `hkbBlendCurveUtils::BlendCurve` as the transition effects decode it. Only
/// curves 0 and 1 appear in the vanilla player graph — 389 smooth against 8
/// linear — so those two are the only ones with a formula here.
nonisolated public enum BehaviorBlendCurve: Sendable {
    public static let smooth = 0
    public static let linear = 1

    /// The destination's share of the blend at `fraction` of the way through.
    /// Smooth is the cubic `3t^2 - 2t^3`, which is flat at both ends; linear is
    /// `t`. Anything else falls back to smooth and is tallied, because writing a
    /// formula for a curve no authored file uses would be inventing it.
    public static func weight(_ fraction: Float, curve: Int) -> Float {
        let time = fraction.isFinite ? min(max(fraction, 0), 1) : 1
        switch curve {
        case linear: return time
        default: return time * time * (3 - 2 * time)
        }
    }

    public static func isKnown(_ curve: Int) -> Bool {
        curve == smooth || curve == linear
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

    /// True while no other transition may replace this one.
    public var isUninterruptible: Bool {
        let mask = BehaviorTransitionFlag.uninterruptibleWhilePlaying
            | BehaviorTransitionFlag.uninterruptibleWhileBlending
        return transitionFlags & mask != 0
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
/// test or the sidebar can check a state path without reaching into the evaluator.
nonisolated public struct BehaviorActiveState: Equatable, Sendable {
    public let machineName: String?
    public let stateId: Int
    public let stateName: String?
    /// The state being blended out of, while a crossfade is running.
    public let previousStateName: String?
    /// The destination's share of the blend: 1 when nothing is in flight.
    public let blendWeight: Float
}
