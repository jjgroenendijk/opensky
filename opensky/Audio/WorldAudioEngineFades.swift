// Time-driven per-source gain ramps for WorldAudioEngine: the primitive a
// music crossfade is built from. Ramps advance from an explicit frame delta
// (never a wall clock), so they are deterministic, testable offline, and freeze
// with the world sim when the renderer pauses. Split from
// WorldAudioEngineSources.swift to stay inside the file-size limits.

import Foundation
import simd

/// A linear gain ramp on one source, advanced by explicit deltas in seconds.
///
/// The ramp interpolates linearly in amplitude (not decibels): simple,
/// deterministic and adequate for the crossfade lengths music uses. If a fade
/// curve ever needs to sound equal-power, that is a change to `gain(atElapsed:)`
/// alone.
nonisolated struct GainFade: Equatable {
    /// Fade gain when the ramp started.
    let start: Float
    /// Fade gain the ramp is heading for, clamped to [0, 1].
    let target: Float
    /// Ramp length in seconds. Never negative; zero completes immediately.
    let duration: Float
    /// Seconds advanced so far.
    private(set) var elapsed: Float = 0
    /// Retire the source once the ramp completes (fade out and stop).
    let stopsAtEnd: Bool

    init(start: Float, target: Float, duration: Float, stopsAtEnd: Bool) {
        self.start = simd_clamp(start, 0, 1)
        self.target = simd_clamp(target, 0, 1)
        self.duration = max(duration, 0)
        self.stopsAtEnd = stopsAtEnd
    }

    /// Completion tolerance in seconds. Advancing by a frame delta accumulates
    /// float error (60 additions of 1/60 do not sum to exactly 1), so a ramp
    /// that lands within a millisecond of its duration counts as done and snaps
    /// to the target — otherwise a fade-out could hover just above silence and
    /// never retire its source.
    static let completionEpsilon: Float = 1e-3

    var isComplete: Bool {
        elapsed + Self.completionEpsilon >= duration
    }

    /// Fade gain at the current elapsed time; exactly `target` once complete.
    var currentGain: Float {
        guard duration > 0, !isComplete else { return target }
        let progress = simd_clamp(elapsed / duration, 0, 1)
        return start + (target - start) * progress
    }

    /// Advances the ramp. A negative or zero delta is ignored, so a stalled or
    /// rewound clock can never run a fade backwards.
    mutating func advance(by deltaTime: Float) {
        guard deltaTime > 0 else { return }
        elapsed = min(elapsed + deltaTime, duration)
    }
}

extension WorldAudioEngine {
    /// Ramps one source's fade gain to `target` over `overSeconds`.
    ///
    /// A second fade requested mid-ramp replaces the first, starting from the
    /// gain the source is at right now — the audible level never jumps. A
    /// duration of zero (or less) applies the target immediately. Returns false
    /// when no source carries that id.
    @discardableResult
    func fadeSource(id: Int, to target: Float, overSeconds duration: Float) -> Bool {
        startFade(id: id, target: target, duration: duration, stopsAtEnd: false)
    }

    /// Ramps one source's fade gain to silence over `overSeconds` and stops it
    /// when the ramp completes, so a departing track retires itself. With a
    /// duration of zero the source stops on this call. Returns false when no
    /// source carries that id.
    @discardableResult
    func fadeOutAndStopSource(id: Int, overSeconds duration: Float) -> Bool {
        startFade(id: id, target: 0, duration: duration, stopsAtEnd: true)
    }

    /// True while a ramp is in flight on that source.
    func isFading(id: Int) -> Bool {
        sources.first { $0.id == id }?.activeFade != nil
    }

    /// Current fade multiplier of a source, or nil when there is no such
    /// source. 1 means "not faded".
    func fadeGain(of id: Int) -> Float? {
        sources.first { $0.id == id }?.fadeGain
    }

    /// Advances every in-flight ramp by one frame and applies the result.
    /// Sources whose fade-out completed are stopped here. Driven by
    /// `tick(listenerCell:deltaTime:)`, which the renderer only calls on
    /// unpaused frames — so a paused world freezes fades without a time jump on
    /// resume.
    func advanceFades(deltaTime: Float) {
        guard deltaTime > 0 else { return }
        var finished: [ActiveAudioSource] = []
        for source in sources {
            guard var fade = source.activeFade else { continue }
            fade.advance(by: deltaTime)
            source.fadeGain = fade.currentGain
            if fade.isComplete {
                source.activeFade = nil
                if fade.stopsAtEnd {
                    finished.append(source)
                }
            } else {
                source.activeFade = fade
            }
            applyVolume(to: source)
        }
        for source in finished {
            stopSource(id: source.id)
        }
    }

    private func startFade(
        id: Int,
        target: Float,
        duration: Float,
        stopsAtEnd: Bool
    ) -> Bool {
        guard let source = sources.first(where: { $0.id == id }) else { return false }
        let fade = GainFade(
            start: source.fadeGain, target: target, duration: duration, stopsAtEnd: stopsAtEnd
        )
        source.fadeGain = fade.currentGain
        applyVolume(to: source)
        if fade.isComplete {
            source.activeFade = nil
            if stopsAtEnd {
                stopSource(id: id)
            }
        } else {
            source.activeFade = fade
        }
        return true
    }
}
