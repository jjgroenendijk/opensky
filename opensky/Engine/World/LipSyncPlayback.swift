// Actor-local `.lip` evaluator. It samples the audio source's thread-safe
// clock snapshot, falls back once to the render-animation clock if that source
// stops answering, maps positional speech slots to TRI names, and writes the
// result into the actor's existing FaceMorphPlayback.

import Foundation

nonisolated enum LipSyncClockMode: String, Equatable {
    case audio
    case wallClock
}

nonisolated struct LipSyncSnapshot: Equatable {
    static let empty = LipSyncSnapshot(
        actor: nil,
        activeLine: nil,
        trackTime: 0,
        clockMode: .audio,
        liveWeights: [:],
        unmappedActiveSlots: [],
        isDecaying: false
    )

    let actor: FormID?
    let activeLine: String?
    let trackTime: Double
    let clockMode: LipSyncClockMode
    let liveWeights: [String: Float]
    let unmappedActiveSlots: [Int]
    let isDecaying: Bool
}

nonisolated private struct LipSyncSession {
    let track: LIPFile
    let clock: VoicePlaybackClock
    let line: String
    let startAnimationTime: Float
    var clockMode = LipSyncClockMode.audio
    var finishAnimationTime: Float?
    var lastWeights: [String: Float] = [:]
}

nonisolated final class LipSyncPlayback: RenderAnimation {
    /// Short enough to avoid a held mouth after audio, long enough to keep the
    /// last open shape from snapping to bind pose on one frame.
    static let decayDuration: Float = 0.15

    let actor: FormID
    private let faceMorph: any LipMorphWeightApplying
    private var session: LipSyncSession?
    private(set) var snapshot = LipSyncSnapshot.empty
    var isEnabled = true {
        didSet {
            if !isEnabled {
                _ = faceMorph.clearLipWeights()
            }
        }
    }

    init(faceMorph: any LipMorphWeightApplying) {
        actor = faceMorph.actor
        self.faceMorph = faceMorph
        snapshot = LipSyncSnapshot(
            actor: actor,
            activeLine: nil,
            trackTime: 0,
            clockMode: .audio,
            liveWeights: [:],
            unmappedActiveSlots: [],
            isDecaying: false
        )
    }

    func start(
        track: LIPFile,
        clock: VoicePlaybackClock,
        line: String,
        animationTime: Float
    ) {
        session = LipSyncSession(
            track: track,
            clock: clock,
            line: line,
            startAnimationTime: animationTime
        )
        snapshot = LipSyncSnapshot(
            actor: actor,
            activeLine: line,
            trackTime: 0,
            clockMode: .audio,
            liveWeights: [:],
            unmappedActiveSlots: [],
            isDecaying: false
        )
    }

    func finish(at animationTime: Float) {
        guard session != nil else { return }
        session?.finishAnimationTime = animationTime
    }

    @discardableResult
    func update(at time: Float) -> Int {
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
        session = current
        snapshot = LipSyncSnapshot(
            actor: actor,
            activeLine: current.line,
            trackTime: trackTime,
            clockMode: current.clockMode,
            liveWeights: mapped.weights,
            unmappedActiveSlots: mapped.unmappedActiveSlots,
            isDecaying: false
        )
        return faceMorph.setLipWeights(mapped.weights)
    }

    @discardableResult
    func resetToBindPose() -> Int {
        session = nil
        snapshot = LipSyncSnapshot(
            actor: actor,
            activeLine: nil,
            trackTime: 0,
            clockMode: .audio,
            liveWeights: [:],
            unmappedActiveSlots: [],
            isDecaying: false
        )
        return faceMorph.clearLipWeights()
    }

    private func updateDecay(session current: LipSyncSession, elapsed: Float) -> Int {
        // Render animation times are Floats, so adding exactly 0.15 seconds can
        // land one representable value below the requested endpoint.
        guard elapsed + 0.000_001 < Self.decayDuration else { return resetToBindPose() }
        let scale = 1 - elapsed / Self.decayDuration
        let weights = current.lastWeights.mapValues { $0 * scale }
        snapshot = LipSyncSnapshot(
            actor: actor,
            activeLine: current.line,
            trackTime: snapshot.trackTime,
            clockMode: current.clockMode,
            liveWeights: weights,
            unmappedActiveSlots: snapshot.unmappedActiveSlots,
            isDecaying: true
        )
        return faceMorph.setLipWeights(weights)
    }
}
