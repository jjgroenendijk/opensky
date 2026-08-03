// `hkbClipGenerator` evaluation (issue #187): local time advance, playback
// modes, triggers, and root-motion extraction, over the spline sampling that
// already existed.
//
// The clip *window* is the part of the animation this generator plays:
// `m_cropStartAmountLocalTime` seconds are cut off the front and
// `m_cropEndAmountLocalTime` off the back, and every time below is measured
// inside that window rather than inside the animation. `m_enforcedDuration`,
// when positive, time-scales the window so it takes exactly that many seconds
// whatever the clip's own length is; `m_playbackSpeed` scales it again.
//
// Triggers are how a clip tells the rest of the graph where it is. Havok's
// annotation tracks are baked into `hkbClipTriggerArray` at export with
// `m_isAnnotation` set, so decoding `hkaAnnotationTrack` separately is not
// needed for the vanilla player graph: an annotation and an authored trigger
// arrive through the same array and fire through the same code below. A
// trigger flagged `m_relativeToEndOfClip` carries an offset from the window end
// rather than from its start — vanilla writes it negative, so it adds — and one
// flagged `m_acyclic` fires on the first cycle only.

import Foundation
import simd

/// The playing part of a clip, in animation-local seconds.
nonisolated private struct BehaviorClipWindow {
    let start: Float
    let length: Float

    init(_ clip: any BehaviorClip, generator: HKBClipGenerator) {
        let duration = max(clip.duration, 0)
        let cropStart = min(max(generator.cropStartAmountLocalTime, 0), duration)
        let cropEnd = min(max(generator.cropEndAmountLocalTime, 0), duration)
        start = cropStart
        length = max(duration - cropStart - cropEnd, 0)
    }
}

nonisolated extension BehaviorGraphInstance {
    /// Advances one clip generator and returns its pose.
    func evaluateClip(
        _ generator: HKBClipGenerator,
        at target: HKXPointerTarget,
        bound: [String: BehaviorVariableValue],
        deltaTime: Float
    ) -> BehaviorPose {
        guard
            let clip = clip(
                named: generator.animationName,
                bindingIndex: generator.animationBindingIndex
            ),
            clip.duration > 0
        else {
            return skeleton.restPose
        }
        let window = BehaviorClipWindow(clip, generator: generator)
        guard window.length > 0 else { return skeleton.restPose }

        var state = markReached(target)
        let wasSeeded = state.hasSeeded
        seedIfNeeded(&state, clip: clip, window: window, generator: generator)
        let advance = step(generator, bound: bound, window: window, deltaTime: deltaTime)
        state.previousLocalTime = state.localTime
        var wrapped = advanceTime(
            &state, by: advance, window: window, bound: bound, generator: generator
        )
        let jumped = applySyncPhase(&state, window: window, justSeeded: !wasSeeded)
        if jumped {
            wrapped = false
        }
        state.phase = state.localTime / window.length

        let samples = clip.samples(at: window.start + state.localTime)
        var pose = BehaviorPose(
            bones: BehaviorPoseMath.applying(samples, to: skeleton.referencePose)
        )
        pose.rootMotion = jumped
            ? resetRootMotion(&state, samples: samples)
            : rootMotion(&state, samples: samples, wrapped: wrapped)
        fireTriggers(generator, state: state, window: window, wrapped: wrapped)
        nodeStates[target] = state
        return pose
    }

    // MARK: - Time

    /// Seconds the clip advances this update, before looping is applied.
    private func step(
        _ generator: HKBClipGenerator,
        bound: [String: BehaviorVariableValue],
        window: BehaviorClipWindow,
        deltaTime: Float
    ) -> Float {
        let speed = bound.float("m_playbackSpeed", or: generator.playbackSpeed)
        let enforced = bound.float("m_enforcedDuration", or: generator.enforcedDuration)
        let scale = enforced > 0 ? window.length / enforced : 1
        let advance = deltaTime * speed * scale
        return advance.isFinite ? advance : 0
    }

    /// Places a freshly activated clip at `m_startTime` and records the root
    /// bone at both window edges, so a wrap can report the travel across the
    /// seam without sampling twice every update.
    private func seedIfNeeded(
        _ state: inout BehaviorNodeState,
        clip: any BehaviorClip,
        window: BehaviorClipWindow,
        generator: HKBClipGenerator
    ) {
        // Keyed on `hasSeeded` rather than on a sampled root pose, because a
        // clip that animates no root bone would otherwise reseed every update
        // and never advance.
        guard !state.hasSeeded else { return }
        state.hasSeeded = true
        state.localTime = min(max(generator.startTime, 0), window.length)
        state.previousLocalTime = state.localTime
        state.windowStartRootPose = rootPose(of: clip.samples(at: window.start))
        state.windowEndRootPose = rootPose(
            of: clip.samples(at: window.start + window.length)
        )
        state.previousRootPose = rootPose(
            of: clip.samples(at: window.start + state.localTime)
        )
    }

    /// Applies `advance` under the generator's playback mode. Returns true when
    /// the clip wrapped past a window edge during this update.
    private func advanceTime(
        _ state: inout BehaviorNodeState,
        by advance: Float,
        window: BehaviorClipWindow,
        bound: [String: BehaviorVariableValue],
        generator: HKBClipGenerator
    ) -> Bool {
        if generator.flags & 0x4 != 0 {
            tally.note(.clipMirrored)
        }
        switch generator.mode {
        case 1, 3:
            // 3 is ping pong, which reverses at each edge rather than wrapping;
            // it is run as a loop and tallied until issue #330 needs otherwise.
            if generator.mode == 3 {
                tally.note(.clipPingPongAsLoop)
            }
            let raw = state.localTime + advance
            state.localTime = raw.truncatingRemainder(dividingBy: window.length)
            if state.localTime < 0 {
                state.localTime += window.length
            }
            let wrapped = raw >= window.length || raw < 0
            if wrapped {
                state.cycleCount += 1
            }
            return wrapped
        case 2:
            tally.note(.clipUserControlled)
            let fraction = bound.float(
                "m_userControlledTimeFraction", or: generator.userControlledTimeFraction
            )
            state.localTime = min(max(fraction, 0), 1) * window.length
            return false
        default:
            state.localTime = min(max(state.localTime + advance, 0), window.length)
            return false
        }
    }

    // MARK: - Synchronization

    /// Forces the clip onto the phase a sync master or a synchronizing
    /// transition published (issue #330), and reports whether that moved it.
    ///
    /// A blender's sync master publishes continuously, so its siblings are
    /// re-aligned every update and stay locked whatever their own lengths are.
    /// A transition publishes seed-only, so the incoming clip starts where the
    /// outgoing one was and then runs on its own.
    private func applySyncPhase(
        _ state: inout BehaviorNodeState,
        window: BehaviorClipWindow,
        justSeeded: Bool
    ) -> Bool {
        guard let pending = pendingClipPhase, pending.value.isFinite else { return false }
        guard !pending.seedOnly || justSeeded else { return false }
        let target = min(max(pending.value, 0), 1) * window.length
        guard target != state.localTime else { return false }
        state.localTime = target
        return true
    }

    // MARK: - Root motion

    /// Drops the travel across a phase jump. A clip forced onto another clip's
    /// phase did not walk there, so the difference between the two samples is
    /// not motion the character made.
    private func resetRootMotion(
        _ state: inout BehaviorNodeState,
        samples: [HKABoneTransformSample]
    ) -> BehaviorRootMotion {
        state.previousRootPose = rootPose(of: samples) ?? state.previousRootPose
        return .identity
    }

    /// The root travel between the previous sample and this one, with the
    /// across-the-seam run added when the clip wrapped.
    private func rootMotion(
        _ state: inout BehaviorNodeState,
        samples: [HKABoneTransformSample],
        wrapped: Bool
    ) -> BehaviorRootMotion {
        guard
            let current = rootPose(of: samples),
            let previous = state.previousRootPose
        else {
            return .identity
        }
        defer { state.previousRootPose = current }
        guard
            wrapped,
            let windowEnd = state.windowEndRootPose,
            let windowStart = state.windowStartRootPose
        else {
            return BehaviorPoseMath.rootMotion(from: previous, to: current)
        }
        return BehaviorPoseMath.concatenating(
            BehaviorPoseMath.rootMotion(from: previous, to: windowEnd),
            BehaviorPoseMath.rootMotion(from: windowStart, to: current)
        )
    }

    private func rootPose(of samples: [HKABoneTransformSample]) -> HKABonePose? {
        samples.first { $0.boneIndex == skeleton.rootBoneIndex }?.pose
    }

    // MARK: - Triggers

    /// Raises every trigger the update stepped over. The interval is half open
    /// on the left, `(previous, current]`, so a trigger at exactly the window
    /// start fires on the wrap that reaches it rather than twice.
    private func fireTriggers(
        _ generator: HKBClipGenerator,
        state: BehaviorNodeState,
        window: BehaviorClipWindow,
        wrapped: Bool
    ) {
        guard
            let arrayTarget = generator.triggers,
            let array = object(at: arrayTarget, as: HKBClipTriggerArray.self)
        else {
            return
        }
        markReached(arrayTarget)
        for trigger in array.triggers {
            guard !trigger.acyclic || state.cycleCount == 0 else { continue }
            // `m_relativeToEndOfClip` measures `m_localTime` *from* the end,
            // and vanilla writes it negative: `MT_JumpLand`'s `JumpLandEnd`
            // trigger carries -0.8, meaning 0.8 seconds before the clip ends.
            // The absolute time is therefore the window length plus a negative
            // offset, not minus it — subtracting put the trigger past the end
            // of the clip, where nothing ever crossed it, which is what parked
            // the player graph in `JumpLandState` forever (issue #189).
            let at = trigger.relativeToEndOfClip
                ? window.length + trigger.localTime
                : trigger.localTime
            guard crossed(at, state: state, window: window, wrapped: wrapped) else {
                continue
            }
            events.raise(
                id: trigger.event.id,
                payload: payload(at: trigger.event.payload)
            )
        }
    }

    /// True when `point` lies in the interval the update covered.
    private func crossed(
        _ point: Float,
        state: BehaviorNodeState,
        window: BehaviorClipWindow,
        wrapped: Bool
    ) -> Bool {
        guard point.isFinite, point >= 0, point <= window.length else { return false }
        guard wrapped else {
            return point > state.previousLocalTime && point <= state.localTime
        }
        return point > state.previousLocalTime || point <= state.localTime
    }

    /// The string an event payload carries, if it carries one.
    func payload(at target: HKXPointerTarget?) -> String? {
        guard let target else { return nil }
        return object(at: target, as: HKBStringEventPayload.self)?.data
    }
}
