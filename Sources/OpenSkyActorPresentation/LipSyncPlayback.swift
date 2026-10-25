// Actor-local `.lip` evaluator. It samples the audio source's thread-safe
// clock snapshot, falls back once to the render-animation clock if that source
// stops answering, maps the track's slots to TRI names and head angles, and
// writes them into the actor's FaceMorphPlayback and skeleton.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyRenderCore
import Synchronization

/// A skeleton whose head a lip track turns, on top of its clip and head tracking.
nonisolated public protocol LipHeadMotionApplying: AnyObject, Sendable {
    var speechHeadMotion: LipHeadMotion { get set }
}

nonisolated public enum LipSyncClockMode: String, Equatable, Sendable {
    case audio
    case wallClock
}

nonisolated public struct LipSyncSnapshot: Equatable, Sendable {
    public static let empty = LipSyncSnapshot(
        activeLine: nil,
        trackTime: 0,
        clockMode: .audio,
        unmappedActiveSlots: [],
        isDecaying: false,
        head: .zero
    )

    public let activeLine: String?
    public let trackTime: Double
    public let clockMode: LipSyncClockMode
    public let unmappedActiveSlots: [Int]
    public let isDecaying: Bool
    public let head: LipHeadMotion
}

nonisolated private struct LipSyncSession: Sendable {
    let track: LIPFile
    let binding: LipTargetBinding
    let clock: VoicePlaybackClock
    let line: String
    let startAnimationTime: Float
    var clockMode = LipSyncClockMode.audio
    var finishAnimationTime: Float?
    var lastWeights: [String: Float] = [:]
    var lastHead = LipHeadMotion.zero
}

nonisolated public final class LipSyncPlayback: RenderAnimation {
    nonisolated private struct State {
        var session: LipSyncSession?
        var snapshot: LipSyncSnapshot
        var isEnabled = true
    }

    /// Short enough to avoid a held mouth after audio, long enough to keep the
    /// last open shape from snapping to bind pose on one frame.
    public static let decayDuration: Float = 0.15

    public let actor: FormID
    private let faceMorph: any LipMorphWeightApplying
    private let head: (any LipHeadMotionApplying)?
    private let state: Mutex<State>

    public var snapshot: LipSyncSnapshot {
        state.withLock { $0.snapshot }
    }

    public var isEnabled: Bool {
        get { state.withLock { $0.isEnabled } }
        set {
            state.withLock { $0.isEnabled = newValue }
            if !newValue {
                _ = faceMorph.clearLipWeights()
                head?.speechHeadMotion = .zero
            }
        }
    }

    /// `head` is the skeleton the head angles turn, or nil to drive the face only.
    public init(faceMorph: any LipMorphWeightApplying, head: (any LipHeadMotionApplying)? = nil) {
        actor = faceMorph.actor
        self.faceMorph = faceMorph
        self.head = head
        state = Mutex(State(snapshot: Self.idleSnapshot()))
    }

    private static func idleSnapshot() -> LipSyncSnapshot {
        LipSyncSnapshot(
            activeLine: nil,
            trackTime: 0,
            clockMode: .audio,
            unmappedActiveSlots: [],
            isDecaying: false,
            head: .zero
        )
    }

    public func start(
        track: LIPFile,
        clock: VoicePlaybackClock,
        line: String,
        animationTime: Float
    ) {
        let session = LipSyncSession(
            track: track,
            binding: LipCurveMapping.binding(
                slotsPerFrame: track.header.slotsPerFrame,
                availableTargets: faceMorph.targetNames
            ),
            clock: clock,
            line: line,
            startAnimationTime: animationTime
        )
        let snapshot = LipSyncSnapshot(
            activeLine: line,
            trackTime: 0,
            clockMode: .audio,
            unmappedActiveSlots: [],
            isDecaying: false,
            head: .zero
        )
        state.withLock {
            $0.session = session
            $0.snapshot = snapshot
        }
    }

    public func finish(at animationTime: Float) {
        state.withLock { $0.session?.finishAnimationTime = animationTime }
    }

    @discardableResult
    public func update(at time: Float) -> Int {
        let (isEnabled, session) = state.withLock { ($0.isEnabled, $0.session) }
        guard isEnabled, var current = session else { return 0 }
        if let finish = current.finishAnimationTime {
            return updateDecay(session: current, elapsed: max(0, time - finish))
        }
        let trackTime: Double
        if current.clockMode == .audio, let position = current.clock.position {
            trackTime = max(0, position)
        } else {
            current.clockMode = .wallClock
            trackTime = Double(max(0, time - current.startAnimationTime))
        }
        let sampled = current.track.sample(at: trackTime)
        let mapped = LipCurveMapping.map(sampled, binding: current.binding)
        current.lastWeights = mapped.weights
        current.lastHead = mapped.head
        if trackTime + 0.000_001 >= current.track.duration {
            current.finishAnimationTime = time
        }
        let snapshot = LipSyncSnapshot(
            activeLine: current.line,
            trackTime: trackTime,
            clockMode: current.clockMode,
            unmappedActiveSlots: mapped.unmappedActiveSlots,
            isDecaying: false,
            head: mapped.head
        )
        state.withLock { [current] in
            $0.session = current
            $0.snapshot = snapshot
        }
        head?.speechHeadMotion = mapped.head
        return faceMorph.setLipWeights(mapped.weights)
    }

    @discardableResult
    public func resetToBindPose() -> Int {
        let idle = Self.idleSnapshot()
        state.withLock {
            $0.session = nil
            $0.snapshot = idle
        }
        head?.speechHeadMotion = .zero
        return faceMorph.clearLipWeights()
    }

    private func updateDecay(session current: LipSyncSession, elapsed: Float) -> Int {
        // Render animation times are Floats, so adding exactly 0.15 seconds can
        // land one representable value below the requested endpoint.
        guard elapsed + 0.000_001 < Self.decayDuration else { return resetToBindPose() }
        let scale = 1 - elapsed / Self.decayDuration
        let weights = current.lastWeights.mapValues { $0 * scale }
        let headMotion = current.lastHead.scaled(by: scale)
        state.withLock {
            $0.snapshot = LipSyncSnapshot(
                activeLine: current.line,
                trackTime: $0.snapshot.trackTime,
                clockMode: current.clockMode,
                unmappedActiveSlots: $0.snapshot.unmappedActiveSlots,
                isDecaying: true,
                head: headMotion
            )
        }
        head?.speechHeadMotion = headMotion
        return faceMorph.setLipWeights(weights)
    }
}
