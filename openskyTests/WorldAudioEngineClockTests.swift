// Playback clock and line-finished callback (item 17.5), under deterministic
// offline rendering: no output device, no decode queue, no wall clock. The
// clock is elapsed-render accounting against the engine's manual-rendering
// sample time, which advances by exactly the frames each
// `renderOffline(_:to:)` call produced — so a rendered frame count converts
// straight into an expected reading.
//
// The material here is a synthetic PCM buffer, not a decoded file: the buffer
// entry point is the same source lifecycle the streamed path uses from the
// player node down, and no WMA fixture may enter the repository.

import AVFAudio
@testable import opensky
import simd
import Testing

@MainActor
struct WorldAudioEngineClockTests {
    private static let sampleRate = 44100.0
    private static let toneSeconds = 0.5

    private func makeRunningEngine() throws -> WorldAudioEngine {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2)
        )
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        engine.isEnabled = true
        try #require(engine.isRunning, "offline engine failed: \(engine.unavailableReason ?? "")")
        return engine
    }

    private func makeToneBuffer(seconds: Double = toneSeconds) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)
        )
        let frameCount = AVAudioFrameCount(seconds * Self.sampleRate)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        let channel = try #require(buffer.floatChannelData?[0])
        for frame in 0 ..< Int(frameCount) {
            channel[frame] = sinf(2 * .pi * 440 * Float(frame) / Float(Self.sampleRate)) * 0.5
        }
        buffer.frameLength = frameCount
        return buffer
    }

    /// Renders `frames` frames offline and returns how many actually rendered.
    @discardableResult
    private func render(_ engine: WorldAudioEngine, frames: Int) throws -> Int {
        let format = engine.engine.manualRenderingFormat
        let chunk = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        var rendered = 0
        while rendered < frames {
            let request = AVAudioFrameCount(min(4096, frames - rendered))
            let status = try engine.engine.renderOffline(request, to: chunk)
            guard status == .success, chunk.frameLength > 0 else { break }
            rendered += Int(chunk.frameLength)
        }
        return rendered
    }

    private func startTone(on engine: WorldAudioEngine, seconds: Double = toneSeconds) throws
        -> Int
    {
        try engine.playPositional(
            buffer: makeToneBuffer(seconds: seconds),
            request: AudioPlayRequest(name: "line", category: .voice, worldPosition: .zero)
        )
    }

    @Test("a source with nothing rendered since it started has no reading, nor has an unknown id")
    func noReadingBeforeRendering() throws {
        let engine = try makeRunningEngine()
        let id = try startTone(on: engine)
        #expect(engine.playbackPosition(ofSource: id) == nil)
        #expect(engine.playbackPosition(ofSource: id + 1000) == nil)
    }

    @Test("the clock advances monotonically with the frames rendered")
    func clockAdvancesWithRenderedFrames() throws {
        let engine = try makeRunningEngine()
        let id = try startTone(on: engine)
        var readings: [Double] = []
        for _ in 0 ..< 4 {
            try render(engine, frames: 4410)
            try readings.append(#require(engine.playbackPosition(ofSource: id)))
        }
        #expect(readings == readings.sorted(), "clock went backwards: \(readings)")
        // Four 0.1 s renders: the clock is the rendered frame count, so the
        // last reading is 0.4 s to within one render quantum.
        let last = try #require(readings.last)
        #expect(abs(last - 0.4) < 0.05, "expected ~0.4 s, read \(last)")
    }

    @Test("the clock reaches the material's length by the time it has all played")
    func clockReachesDuration() throws {
        let engine = try makeRunningEngine()
        let id = try startTone(on: engine)
        try render(engine, frames: Int(Self.toneSeconds * Self.sampleRate))
        let position = try #require(engine.playbackPosition(ofSource: id))
        #expect(abs(position - Self.toneSeconds) < 0.05, "expected ~0.5 s, read \(position)")
    }

    @Test("a source that plays out reports finished once, and only on its own end")
    func finishedCallbackFiresOnce() async throws {
        let engine = try makeRunningEngine()
        var finished: [Int] = []
        engine.onSourceFinished = { finished.append($0) }
        let id = try startTone(on: engine)
        try render(engine, frames: Int(Self.toneSeconds * Self.sampleRate) + 8192)
        // The player node's completion handler fires on an AVFAudio-internal
        // thread and hops to the main actor to set `bufferFinished`, so the
        // test has to suspend — not spin — before ticking the engine that
        // reads that flag.
        try await Task.sleep(for: .milliseconds(100))
        engine.tick(listenerCell: CellCoordinate(x: 0, y: 0))
        #expect(finished == [id])
        engine.tick(listenerCell: CellCoordinate(x: 0, y: 0))
        #expect(finished == [id], "a retired source must not report twice")
        #expect(engine.playbackPosition(ofSource: id) == nil, "a retired source has no reading")
    }

    @Test("two sources started at different times read different positions")
    func positionsAreRelativeToEachSourcesStart() throws {
        let engine = try makeRunningEngine()
        let first = try startTone(on: engine)
        try render(engine, frames: 8820)
        let second = try startTone(on: engine)
        try render(engine, frames: 4410)
        let early = try #require(engine.playbackPosition(ofSource: first))
        let late = try #require(engine.playbackPosition(ofSource: second))
        #expect(abs(early - 0.3) < 0.05, "first source read \(early)")
        #expect(abs(late - 0.1) < 0.05, "second source read \(late)")
    }

    @Test("a source stopped by hand does not report finished")
    func stoppingDoesNotReportFinished() throws {
        let engine = try makeRunningEngine()
        var finished: [Int] = []
        engine.onSourceFinished = { finished.append($0) }
        let id = try startTone(on: engine)
        try render(engine, frames: 4410)
        #expect(engine.stopSource(id: id))
        engine.tick(listenerCell: CellCoordinate(x: 0, y: 0))
        #expect(finished.isEmpty)
    }

    @Test("the panel snapshot carries the same clock reading the engine reports")
    func snapshotCarriesPosition() throws {
        let engine = try makeRunningEngine()
        let id = try startTone(on: engine)
        try render(engine, frames: 4410)
        let source = try #require(engine.statsSnapshot().sources.first)
        let position = try #require(source.positionSeconds)
        let direct = try #require(engine.playbackPosition(ofSource: id))
        #expect(abs(position - direct) < 0.001)
    }
}
