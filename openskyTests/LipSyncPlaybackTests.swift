@testable import opensky
import Testing

@Suite("Audio-clock lip-sync playback")
struct LipSyncPlaybackTests {
    @Test("a synthetic audio clock produces the known interpolated weight sequence")
    func syntheticClockIntegration() throws {
        let morph = LipMorphSink()
        let playback = LipSyncPlayback(faceMorph: morph)
        let clock = VoicePlaybackClock()
        try playback.start(
            track: LIPFile(data: LIPFixture.file()),
            clock: clock,
            line: "synthetic line",
            animationTime: 10
        )

        #expect(playback.update(at: 10) == 1)
        #expect(abs((morph.weights["Aah"] ?? 0) - 0.2) < 0.0001)
        #expect(abs((morph.weights["BigAah"] ?? 0) - 0.4) < 0.0001)

        clock.publish(0.5 / LIPFile.framesPerSecond)
        _ = playback.update(at: 10.5)
        #expect(abs((morph.weights["Aah"] ?? 0) - 0.5) < 0.0001)
        #expect(abs((morph.weights["BigAah"] ?? 0) - 0.5) < 0.0001)
        #expect(playback.snapshot.clockMode == .audio)
        #expect(playback.snapshot.activeLine == "synthetic line")
    }

    @Test("a missing source switches once to the line-anchored wall clock")
    func wallClockFallbackDoesNotResync() throws {
        let morph = LipMorphSink()
        let playback = LipSyncPlayback(faceMorph: morph)
        let clock = VoicePlaybackClock()
        try playback.start(
            track: LIPFile(data: LIPFixture.file()),
            clock: clock,
            line: "fallback",
            animationTime: 5
        )
        clock.publish(nil)
        _ = playback.update(at: 5.01)
        let fallbackTime = playback.snapshot.trackTime
        clock.publish(0.9)
        _ = playback.update(at: 5.02)

        #expect(playback.snapshot.clockMode == .wallClock)
        #expect(fallbackTime > 0)
        #expect(playback.snapshot.trackTime < 0.03)
    }

    @Test("wall-clock fallback releases when the lip track ends")
    func wallClockFallbackReleasesAtTrackEnd() throws {
        let morph = LipMorphSink()
        let playback = LipSyncPlayback(faceMorph: morph)
        let clock = VoicePlaybackClock()
        let track = try LIPFile(data: LIPFixture.file())
        playback.start(track: track, clock: clock, line: "fallback end", animationTime: 5)
        clock.publish(nil)
        _ = playback.update(at: 5 + Float(track.duration))
        _ = playback.update(at: 5 + Float(track.duration) + LipSyncPlayback.decayDuration / 2)

        #expect(playback.snapshot.isDecaying)
        #expect(abs((morph.weights["Aah"] ?? 0) - 0.4) < 0.0001)
    }

    @Test("finished lines decay instead of snapping and then clear")
    func decayRamp() throws {
        let morph = LipMorphSink()
        let playback = LipSyncPlayback(faceMorph: morph)
        let clock = VoicePlaybackClock()
        try playback.start(
            track: LIPFile(data: LIPFixture.file()),
            clock: clock,
            line: "decay",
            animationTime: 1
        )
        _ = playback.update(at: 1)
        playback.finish(at: 1)
        _ = playback.update(at: 1 + LipSyncPlayback.decayDuration / 2)

        #expect(playback.snapshot.isDecaying)
        #expect(abs((morph.weights["Aah"] ?? 0) - 0.1) < 0.0001)

        _ = playback.update(at: 1 + LipSyncPlayback.decayDuration)
        #expect(morph.weights.isEmpty)
        #expect(playback.snapshot.activeLine == nil)
    }
}

nonisolated private final class LipMorphSink: LipMorphWeightApplying {
    let actor = FormID(0x14)
    let targetNames = ["Aah", "BigAah"]
    private(set) var weights: [String: Float] = [:]

    @discardableResult
    func setLipWeights(_ weights: [String: Float]) -> Int {
        self.weights = weights
        return 1
    }

    @discardableResult
    func clearLipWeights() -> Int {
        weights = [:]
        return 1
    }
}
