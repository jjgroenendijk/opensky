// `hkbClipGenerator` evaluation: local time, playback modes, triggers and root motion.
// Times are inside the crop window; `m_enforcedDuration` and `m_playbackSpeed` scale it.
// Triggers come from `hkbClipTriggerArray` and from the animation's
// `hkaAnnotationTrack`s. Vanilla footsteps (`FootLeft`, `FootRight`) are annotations
// with empty `m_triggers`, so both sources fire through one crossing test.

import Foundation
import OpenSkyFormatsAnimation
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
    public func evaluateClip(
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
        pose.rootMotion = rootMotion(
            &state, clip: clip, samples: samples, wrapped: wrapped, jumped: jumped
        )
        fireTriggers(generator, state: state, window: window, wrapped: wrapped)
        fireAnnotations(
            clip, state: state, window: window, wrapped: wrapped, justSeeded: !wasSeeded
        )
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
            // 3 is ping pong, which reverses at each edge. It runs as a loop and is
            // tallied.
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

    /// Forces the clip onto a published phase and reports whether it moved. A sync
    /// master publishes every update, keeping siblings locked; a transition publishes
    /// once, so the incoming clip then runs on its own.
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

    /// This update's root travel, or identity. A clip without `m_extractedMotion`
    /// animates in place, and differencing its root wander moved the capsule; a phase
    /// jump is not walking either. The previous root pose is still tracked.
    private func rootMotion(
        _ state: inout BehaviorNodeState,
        clip: any BehaviorClip,
        samples: [HKABoneTransformSample],
        wrapped: Bool,
        jumped: Bool
    ) -> BehaviorRootMotion {
        guard
            let current = rootPose(of: samples),
            let previous = state.previousRootPose
        else {
            state.previousRootPose = rootPose(of: samples) ?? state.previousRootPose
            return .identity
        }
        defer { state.previousRootPose = current }
        guard clip.carriesExtractedMotion else { return .identity }
        // A clip that does carry a reference frame has its travel approximated
        // from the root bone, because `hkaAnimatedReferenceFrame` itself is not
        // decoded. Tallied so the approximation is visible rather than assumed.
        tally.note(.clipExtractedMotionApproximated)
        guard !jumped else { return .identity }
        guard
            wrapped,
            let windowEnd = state.windowEndRootPose,
            let windowStart = state.windowStartRootPose
        else {
            return BehaviorPoseMath.rootMotion(
                from: previous, to: current, isExtracted: true
            )
        }
        return BehaviorPoseMath.concatenating(
            BehaviorPoseMath.rootMotion(from: previous, to: windowEnd, isExtracted: true),
            BehaviorPoseMath.rootMotion(from: windowStart, to: current, isExtracted: true)
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
            // `m_relativeToEndOfClip` offsets are negative (`MT_JumpLand`'s
            // `JumpLandEnd` is -0.8), so add them to the window length. Subtracting
            // put the trigger past the end, and the graph never left `JumpLandState`.
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

    /// Raises each clip annotation the update stepped over, by name, measured from the
    /// window start. An unknown event name is ignored. The seeding update is closed at
    /// its start, so `1HM_Equip.hkx`'s `BeginWeaponDraw` at 0.0 fires; later ones are half-open.
    private func fireAnnotations(
        _ clip: any BehaviorClip,
        state: BehaviorNodeState,
        window: BehaviorClipWindow,
        wrapped: Bool,
        justSeeded: Bool
    ) {
        for annotation in clip.annotations {
            let at = annotation.time - window.start
            guard
                crossed(
                    at, state: state, window: window,
                    wrapped: wrapped, includingStart: justSeeded
                )
            else {
                continue
            }
            events.raise(named: annotation.text)
        }
    }

    /// True when `point` lies in the interval the update covered.
    ///
    /// `includingStart` closes the interval's left edge, which only the update
    /// that seeded the clip asks for.
    private func crossed(
        _ point: Float,
        state: BehaviorNodeState,
        window: BehaviorClipWindow,
        wrapped: Bool,
        includingStart: Bool = false
    ) -> Bool {
        guard point.isFinite, point >= 0, point <= window.length else { return false }
        let afterStart = includingStart
            ? point >= state.previousLocalTime
            : point > state.previousLocalTime
        guard wrapped else {
            return afterStart && point <= state.localTime
        }
        return afterStart || point <= state.localTime
    }

    /// The string an event payload carries, if it carries one.
    public func payload(at target: HKXPointerTarget?) -> String? {
        guard let target else { return nil }
        return object(at: target, as: HKBStringEventPayload.self)?.data
    }
}
