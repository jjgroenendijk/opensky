// Deterministic coverage for the non-positional (music) playback path:
// category-submix routing, stereo material, and the budget/purge exemptions
// (docs/engine/audio.md). Offline manual rendering only — no output device, no
// decode-queue timing. Gain ramps are covered by WorldAudioEngineFadeTests.

import AVFAudio
@testable import OpenSkyAudio
@testable import OpenSkyFormatsCore
import OpenSkyFormatsTesting
import simd
import Testing

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
