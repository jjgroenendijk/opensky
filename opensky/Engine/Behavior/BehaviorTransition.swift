// Transitions in flight (issue #330): the flag map a `hkbStateMachineTransitionInfo`
// carries, the crossfade one `hkbBlendingTransitionEffect` runs, and the blend
// curve that shapes it.
//
// The flag map below is not taken on faith. It comes from the same open-source
// lineage as the byte layouts (hkxparse/HKX2Library, ZeldaMods Havok wiki; see
// `docs/decisions/havok-behavior-scope.md`), and every bit this file acts on was
// then checked against the local install by the probe recorded in
// `docs/engine/behavior-runtime.md`:
//
// * `0x100` is set on 3,340 of the 3,769 transitions and on exactly the
//   transitions that carry no `m_condition` pointer, which is what
//   `FLAG_DISABLE_CONDITION` means.
// * `0x400` and `0x800` appear only inside `m_wildcardTransitions` arrays,
//   which is what the two wildcard bits mean.
// * `0x2000` appears only where `m_toNestedStateId` is a state id the
//   destination's nested machine declares.
//
// Bits the vanilla player graph never sets (`0x8`, `0x40`, `0x80`, `0x4000`)
// are named for completeness and not acted on.

import Foundation

/// `hkbStateMachineTransitionInfo::TransitionFlags`, as far as the vanilla
/// player graph exercises them.
nonisolated enum BehaviorTransitionFlag {
    /// The transition may only trigger inside `m_triggerInterval`.
    static let useTriggerInterval = 0x1
    /// The transition may only start inside `m_initiateInterval`.
    static let useInitiateInterval = 0x2
    /// No other transition may replace this one while its destination plays.
    static let uninterruptibleWhilePlaying = 0x4
    /// No other transition may replace this one while it is still blending.
    static let uninterruptibleWhileBlending = 0x8
    /// The state change waits for the blend to finish.
    static let delayStateChange = 0x10
    /// The transition is authored but switched off.
    static let disabled = 0x20
    /// `m_condition` is not evaluated. Set by the exporter on every transition
    /// that carries no condition object.
    static let disableCondition = 0x100
    /// A transition whose destination is the state it starts from may fire.
    static let allowSelfTransition = 0x200
    /// The transition lives in a wildcard array and applies from any state.
    static let globalWildcard = 0x400
    static let localWildcard = 0x800
    /// `m_fromNestedStateId` / `m_toNestedStateId` name a state of a nested
    /// machine rather than of this one.
    static let fromNestedStateIsValid = 0x1000
    static let toNestedStateIsValid = 0x2000
}

/// `hkbBlendingTransitionEffect::FlagBits`. Only the sync bit is acted on; the
/// others describe how root motion crosses the blend, which item 14.5 owns once
/// a character controller exists to disagree with it.
nonisolated enum BehaviorTransitionEffectFlag {
    static let ignoreFromGenerator = 0x1
    /// Align the incoming generator's clip time with the outgoing one's.
    static let sync = 0x2
    static let ignoreWorldFromModel = 0x4
    static let ignoreToGenerator = 0x8
}

/// `hkbBlendCurveUtils::BlendCurve` as the transition effects decode it. Only
/// curves 0 and 1 appear in the vanilla player graph — 389 smooth against 8
/// linear — so those two are the only ones with a formula here.
nonisolated enum BehaviorBlendCurve {
    static let smooth = 0
    static let linear = 1

    /// The destination's share of the blend at `fraction` of the way through.
    /// Smooth is the cubic `3t^2 - 2t^3`, which is flat at both ends; linear is
    /// `t`. Anything else falls back to smooth and is tallied, because writing a
    /// formula for a curve no authored file uses would be inventing it.
    static func weight(_ fraction: Float, curve: Int) -> Float {
        let time = fraction.isFinite ? min(max(fraction, 0), 1) : 1
        switch curve {
        case linear: return time
        default: return time * time * (3 - 2 * time)
        }
    }

    static func isKnown(_ curve: Int) -> Bool {
        curve == smooth || curve == linear
    }
}

/// One crossfade in progress inside a state machine. Built when the transition
/// starts and stepped by every update until it is finished.
nonisolated struct BehaviorTransition: Equatable {
    /// The state the machine is blending out of. The machine's own
    /// `currentStateId` is already the destination: the state change happens
    /// when the transition starts and the effect only fades the old pose.
    var fromStateId: Int
    var elapsed: Float
    var duration: Float
    var blendCurve: Int
    /// `hkbBlendingTransitionEffect::m_flags`.
    var effectFlags: Int
    /// `hkbStateMachineTransitionInfo::m_flags` of the transition that started
    /// this blend, so the interruption rules can read them back.
    var transitionFlags: Int

    /// How much of the destination pose is showing.
    var weight: Float {
        guard duration > 0 else { return 1 }
        return BehaviorBlendCurve.weight(elapsed / duration, curve: blendCurve)
    }

    var isFinished: Bool {
        !(elapsed < duration)
    }

    var ignoresFromGenerator: Bool {
        effectFlags & BehaviorTransitionEffectFlag.ignoreFromGenerator != 0
    }

    var synchronizes: Bool {
        effectFlags & BehaviorTransitionEffectFlag.sync != 0
    }

    /// True while no other transition may replace this one.
    var isUninterruptible: Bool {
        let mask = BehaviorTransitionFlag.uninterruptibleWhilePlaying
            | BehaviorTransitionFlag.uninterruptibleWhileBlending
        return transitionFlags & mask != 0
    }
}

/// The runtime state of one `hkbStateMachine`. Kept apart from
/// `BehaviorNodeState` because it outlives deactivation: `m_startStateMode` 2
/// re-enters the state that was current when the machine stopped, and 121 of
/// the 1,963 machines in the vanilla player graph are authored that way.
nonisolated struct BehaviorMachineState: Equatable {
    var currentStateId = -1
    /// The state before the current one, for `m_returnToPreviousStateEventId`.
    var previousStateId = -1
    /// True between entering the start state and deactivation.
    var isEntered = false
    var transition: BehaviorTransition?
}

/// What one machine is doing right now, in names rather than ids. Published per
/// update so a test — and item 14.6's sidebar readout — can assert a state path
/// without reaching into the evaluator.
nonisolated struct BehaviorActiveState: Equatable, Sendable {
    let machineName: String?
    let stateId: Int
    let stateName: String?
    /// The state being blended out of, while a crossfade is running.
    let previousStateName: String?
    /// The destination's share of the blend: 1 when nothing is in flight.
    let blendWeight: Float
}
