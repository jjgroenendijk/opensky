// Actor-local `.lip` evaluator. It samples the audio source's thread-safe
// clock snapshot, falls back once to the render-animation clock if that source
// stops answering, maps positional speech slots to TRI names, and writes the
// result into the actor's existing FaceMorphPlayback.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyRendering
import Synchronization

nonisolated public enum LipSyncClockMode: String, Equatable, Sendable {
    case audio
    case wallClock
}

nonisolated public struct LipSyncSnapshot: Equatable, Sendable {
    public static let empty = LipSyncSnapshot(
        actor: nil,
        activeLine: nil,
        trackTime: 0,
        clockMode: .audio,
        liveWeights: [:],
        unmappedActiveSlots: [],
        isDecaying: false,
        layout: nil
    )

    public let actor: FormID?
    public let activeLine: String?
    public let trackTime: Double
    public let clockMode: LipSyncClockMode
    public let liveWeights: [String: Float]
    public let unmappedActiveSlots: [Int]
    public let isDecaying: Bool
    /// How the active track framed itself: header size, tuple width, vocabulary and slot
    /// stride. The corpus has several of each, so the panel shows which one this used.
    public let layout: String?
}

nonisolated extension LIPFile {
    /// One line naming the layout this track decoded as.
    public var layoutDescription: String {
        "header \(header.headerSize) B · tuple \(header.tupleWidth) · "
            + "vocab \(header.targetCount) · \(header.slotsPerFrame) slots/frame"
    }
}

nonisolated private struct LipSyncSession: Sendable {
    let track: LIPFile
    let clock: VoicePlaybackClock
    let line: String
    let startAnimationTime: Float
    var clockMode = LipSyncClockMode.audio
    var finishAnimationTime: Float?
    var lastWeights: [String: Float] = [:]
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
            }
        }
    }

    public init(faceMorph: any LipMorphWeightApplying) {
        actor = faceMorph.actor
        self.faceMorph = faceMorph
        state = Mutex(State(snapshot: Self.idleSnapshot(actor: faceMorph.actor)))
    }

    private static func idleSnapshot(actor: FormID) -> LipSyncSnapshot {
        LipSyncSnapshot(
            actor: actor,
            activeLine: nil,
            trackTime: 0,
            clockMode: .audio,
            liveWeights: [:],
            unmappedActiveSlots: [],
            isDecaying: false,
            layout: nil
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
            clock: clock,
            line: line,
            startAnimationTime: animationTime
        )
        let snapshot = LipSyncSnapshot(
            actor: actor,
            activeLine: line,
            trackTime: 0,
            clockMode: .audio,
            liveWeights: [:],
            unmappedActiveSlots: [],
            isDecaying: false,
            layout: track.layoutDescription
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
        let mapped = LipVisemeMapping.map(
            sampled,
            availableTargets: Set(faceMorph.targetNames)
        )
        current.lastWeights = mapped.weights
        if trackTime + 0.000_001 >= current.track.duration {
            current.finishAnimationTime = time
        }
        let snapshot = LipSyncSnapshot(
            actor: actor,
            activeLine: current.line,
            trackTime: trackTime,
            clockMode: current.clockMode,
            liveWeights: mapped.weights,
            unmappedActiveSlots: mapped.unmappedActiveSlots,
            isDecaying: false,
            layout: current.track.layoutDescription
        )
        state.withLock { [current] in
            $0.session = current
            $0.snapshot = snapshot
        }
        return faceMorph.setLipWeights(mapped.weights)
    }

    @discardableResult
    public func resetToBindPose() -> Int {
        let idle = Self.idleSnapshot(actor: actor)
        state.withLock {
            $0.session = nil
            $0.snapshot = idle
        }
        return faceMorph.clearLipWeights()
    }

    private func updateDecay(session current: LipSyncSession, elapsed: Float) -> Int {
        // Render animation times are Floats, so adding exactly 0.15 seconds can
        // land one representable value below the requested endpoint.
        guard elapsed + 0.000_001 < Self.decayDuration else { return resetToBindPose() }
        let scale = 1 - elapsed / Self.decayDuration
        let weights = current.lastWeights.mapValues { $0 * scale }
        state.withLock {
            $0.snapshot = LipSyncSnapshot(
                actor: actor,
                activeLine: current.line,
                trackTime: $0.snapshot.trackTime,
                clockMode: current.clockMode,
                liveWeights: weights,
                unmappedActiveSlots: $0.snapshot.unmappedActiveSlots,
                isDecaying: true,
                layout: current.track.layoutDescription
            )
        }
        return faceMorph.setLipWeights(weights)
    }
}
