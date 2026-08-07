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
// Triggers are how a clip tells the rest of the graph where it is, and they
// reach a generator two ways. `hkbClipTriggerArray` holds the authored ones,
// each raised as playback crosses its time; a trigger flagged
// `m_relativeToEndOfClip` carries an offset from the window end rather than
// from its start — vanilla writes it negative, so it adds — and one flagged
// `m_acyclic` fires on the first cycle only.
//
// The other way is the animation's own `hkaAnnotationTrack`s, and they are not
// the same thing however much the `m_isAnnotation` flag suggests they might be.
// Skyrim's locomotion clip generators carry an *empty* `m_triggers`: the
// footstep tags `FootLeft` and `FootRight` are annotations inside
// `mt_walkforward.hkx` and its siblings, so a runtime that reads only the
// trigger array walks in perfect silence (issues #385, #394). Both sources fire
// through the same crossing test below, and both are cyclic — an annotation is
// a mark on the animation, so it comes round again every loop.

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

    /// The root travel this update produced, or the identity when there is
    /// none to report.
    ///
    /// Two things zero it. A clip that carries no `m_extractedMotion` animates
    /// in place, so its root bone is decoration: differencing it reports the
    /// fraction of a unit the authored curve wanders between two samples, and
    /// at a 1/120 s step that fraction reads as a double-digit speed. Feeding
    /// it forward moved the capsule — backwards, on the steps where the wander
    /// ran against the walk direction (issue #370). A phase jump zeroes it for
    /// the other reason: a clip forced onto another clip's phase did not walk
    /// there, so the difference between its two samples is not motion the
    /// character made.
    ///
    /// The previous root pose is tracked in both cases, so a clip that starts
    /// reporting travel measures it from where it actually is.
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

    /// Raises every annotation of the clip itself that the update stepped over,
    /// by the name the annotation spells.
    ///
    /// Annotation times are measured in the animation, and every other time
    /// here is measured in the clip window, so the window start comes off
    /// first. An annotation outside the window is one the crop cut away, and
    /// `crossed` drops it for being out of range.
    ///
    /// A graph that declares no event by that name is not an error: an
    /// annotation is a mark on an animation, and the same animation is played
    /// by behavior files that care about different marks. `raise(named:)`
    /// answers false and nothing happens.
    ///
    /// The update that seeded the clip covers the closed interval from the
    /// start time rather than the half-open one every later update covers
    /// (issue #403). Vanilla authors annotations *at* the first frame and means
    /// them: `1HM_Equip.hkx` carries `BeginWeaponDraw` at 0.0, and with the
    /// half-open rule that mark could never fire, which left the weapon on the
    /// sheathed node for the whole draw. Later updates stay half-open so a mark
    /// the previous update already crossed does not fire twice.
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
    func payload(at target: HKXPointerTarget?) -> String? {
        guard let target else { return nil }
        return object(at: target, as: HKBStringEventPayload.self)?.data
    }
}
