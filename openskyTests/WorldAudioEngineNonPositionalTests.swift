// Deterministic coverage for the non-positional (music) playback path:
// category-submix routing, stereo material, and the budget/purge exemptions
// (docs/engine/audio.md). Offline manual rendering only — no output device, no
// decode-queue timing. Gain ramps are covered by WorldAudioEngineFadeTests.

import AVFAudio
@testable import opensky
import simd
import Testing

/// Shared offline fixtures for the non-positional and fade suites.
@MainActor
enum MusicAudioFixture {
    static let sampleRate = 44100.0

    static func makeRunningEngine() throws -> WorldAudioEngine {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        )
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        engine.isEnabled = true
        try #require(engine.isRunning, "offline engine failed: \(engine.unavailableReason ?? "")")
        return engine
    }

    /// Stereo tone, the shape music material has.
    static func makeStereoBuffer(seconds: Double = 0.25) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        )
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        let channels = try #require(buffer.floatChannelData)
        for frame in 0 ..< Int(frameCount) {
            let sample = sinf(2 * .pi * 440 * Float(frame) / Float(sampleRate)) * 0.5
            channels[0][frame] = sample
            channels[1][frame] = sample
        }
        buffer.frameLength = frameCount
        return buffer
    }

    /// Root-mean-square of exactly 0.2 s of offline render across both channels.
    ///
    /// `scheduleBuffer` hands the buffer to the player node asynchronously, so
    /// rendering can begin with silence or start partway through a chunk. The
    /// measurement begins at the first frame carrying signal and covers a fixed
    /// number of frames: how long the node took to start is machine load, not
    /// signal level (issues #240 and #255).
    static func renderRMS(_ engine: WorldAudioEngine) throws -> Float {
        let format = engine.engine.manualRenderingFormat
        let chunk = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        var sum: Float = 0
        var measuredFrames = 0
        var started = false
        var attempts = 0
        let targetFrames = 8820
        while measuredFrames < targetFrames, attempts < 64 {
            attempts += 1
            let status = try engine.engine.renderOffline(4096, to: chunk)
            guard status == .success else { continue }
            let channels = try #require(chunk.floatChannelData)
            var firstFrame = 0
            if !started {
                firstFrame = Int(chunk.frameLength)
                findSignal: for frame in 0 ..< Int(chunk.frameLength) {
                    for channel in 0 ..< Int(format.channelCount)
                        where channels[channel][frame] != 0
                    {
                        firstFrame = frame
                        started = true
                        break findSignal
                    }
                }
                guard started else { continue }
            }
            let frameCount = min(
                Int(chunk.frameLength) - firstFrame,
                targetFrames - measuredFrames
            )
            for channel in 0 ..< Int(format.channelCount) {
                for frame in firstFrame ..< firstFrame + frameCount {
                    let sample = channels[channel][frame]
                    sum += sample * sample
                }
            }
            measuredFrames += frameCount
        }
        try #require(measuredFrames == targetFrames, "offline player produced no signal")
        return sqrtf(sum / Float(measuredFrames * Int(format.channelCount)))
    }

    @discardableResult
    static func playMusic(
        _ engine: WorldAudioEngine, name: String = "music\\test.xwm", gain: Float = 1
    ) throws -> Int {
        try engine.playNonPositional(
            buffer: makeStereoBuffer(),
            request: .nonPositional(name: name, category: .music, gain: gain, loops: true)
        )
    }

    /// Mono one-shot through the positional path — the environment node only
    /// spatializes mono inputs.
    static func playEffect(
        _ engine: WorldAudioEngine, name: String, at worldPosition: SIMD3<Float> = .zero
    ) throws {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        )
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
        buffer.frameLength = 128
        try engine.playPositional(buffer: buffer, request: AudioPlayRequest(
            name: name, category: .effects, worldPosition: worldPosition
        ))
    }
}

@MainActor
struct WorldAudioEngineNonPositionalTests {
    @Test
    func nonPositionalSourceRoutesToTheCategorySubmixInStereo() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        let id = try MusicAudioFixture.playMusic(engine)
        let source = try #require(engine.sources.first { $0.id == id })
        #expect(source.routing == .nonPositional)
        #expect(!source.isPositional)
        #expect(source.worldPosition == .zero)
        #expect(source.node.outputFormat(forBus: 0).channelCount == 2)
        let mixer = try #require(engine.categoryMixers[.music])
        let destinations = engine.engine.outputConnectionPoints(for: source.node, outputBus: 0)
        #expect(destinations.contains { $0.node === mixer })
    }

    @Test
    func nonPositionalSourceIsAudible() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        try MusicAudioFixture.playMusic(engine)
        #expect(try MusicAudioFixture.renderRMS(engine) > 1e-2)
    }

    /// The category factor must be applied once (at the submix), not twice
    /// (submix and node), on the non-positional path.
    @Test
    func musicCategoryVolumeAppliesOnce() throws {
        let loud = try MusicAudioFixture.makeRunningEngine()
        try MusicAudioFixture.playMusic(loud)
        let loudRMS = try MusicAudioFixture.renderRMS(loud)

        let quiet = try MusicAudioFixture.makeRunningEngine()
        quiet.setVolume(0.25, for: .music)
        try MusicAudioFixture.playMusic(quiet)
        let quietRMS = try MusicAudioFixture.renderRMS(quiet)

        let ratio = quietRMS / loudRMS
        #expect(abs(ratio - 0.25) < 0.02, "ratio \(ratio) should be ~0.25, not squared")
        let source = try #require(quiet.sources.first)
        #expect(abs(quiet.effectiveGain(of: source) - 0.25) < 1e-5)
    }

    /// A music bed has no meaningful cell, so the cell purge must leave it be
    /// while it retires the positional source that streamed away.
    @Test
    func nonPositionalSourceSurvivesTheCellPurge() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        try MusicAudioFixture.playMusic(engine, name: "music")
        try MusicAudioFixture.playEffect(
            engine,
            name: "far",
            at: SIMD3(Float(WorldAudioEngine.cellPurgeRadius + 2) * 4096, 0, 0)
        )
        engine.tick(listenerCell: CellCoordinate(x: 0, y: 0), deltaTime: 1 / 60)
        #expect(engine.sources.map(\.name) == ["music"])
    }

    /// The FIFO budget counts positional sources only: a burst of effects fills
    /// the cap without evicting the music bed.
    @Test
    func nonPositionalSourceIsExemptFromTheFIFOBudget() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        try MusicAudioFixture.playMusic(engine, name: "music")
        for index in 0 ..< (WorldAudioEngine.maxConcurrentSources + 2) {
            try MusicAudioFixture.playEffect(engine, name: "effect-\(index)")
        }
        let names = engine.sources.map(\.name)
        #expect(names.contains("music"), "music must survive the burst, got \(names)")
        #expect(
            engine.sources.count(where: \.isPositional) == WorldAudioEngine.maxConcurrentSources
        )
        #expect(!names.contains("effect-0"), "the oldest positional source must be evicted")
    }

    @Test
    func disabledEngineRefusesNonPositionalPlayback() throws {
        let format = try #require(
            AVAudioFormat(
                standardFormatWithSampleRate: MusicAudioFixture.sampleRate, channels: 2
            )
        )
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        #expect(throws: AudioEngineError.notRunning) {
            try engine.playNonPositional(
                buffer: MusicAudioFixture.makeStereoBuffer(),
                request: .nonPositional(name: "music", category: .music)
            )
        }
    }

    /// The streamed path keeps the file's channel layout instead of downmixing
    /// to mono the way the positional path must.
    @Test
    func nonPositionalStreamedPlaybackKeepsTheFileChannelCount() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        let id = try engine.playNonPositional(
            fileData: XWMFixture.file(packetCount: 3),
            request: .nonPositional(name: "music\\stream.xwm", category: .music)
        )
        let source = try #require(engine.sources.first { $0.id == id })
        #expect(source.node.outputFormat(forBus: 0).channelCount == 2)
        engine.stopAllSources()
    }
}
