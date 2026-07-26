// Per-category mute and solo (M9.2.4), proven through the same offline
// manual-rendering harness as WorldAudioEngineTests: no output device, no
// audible playback. Semantics under test (docs/engine/audio.md): a muted
// category contributes zero gain, a solo silences every other category, mute
// and solo are independent filters that both must pass, and neither disturbs
// the category volume a slider left behind.

import AVFAudio
@testable import opensky
import simd
import Testing

@MainActor
struct WorldAudioEngineMuteSoloTests {
    private static let sampleRate = 44100.0
    /// ~1 m in native units.
    private static let oneMeterUnits: Float = 1 / AudioSpace.metersPerUnit

    private func makeRunningEngine() throws -> WorldAudioEngine {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2)
        )
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        engine.isEnabled = true
        try #require(engine.isRunning, "offline engine failed: \(engine.unavailableReason ?? "")")
        engine.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        return engine
    }

    private func makeToneBuffer() throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)
        )
        let frameCount = AVAudioFrameCount(0.25 * Self.sampleRate)
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

    /// Renders ~0.2 s and returns the summed per-channel RMS.
    private func renderRMS(_ engine: WorldAudioEngine) throws -> Float {
        let format = engine.engine.manualRenderingFormat
        let chunk = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        var sums = [Float](repeating: 0, count: Int(format.channelCount))
        var frames = 0
        while frames < 8820 {
            let status = try engine.engine.renderOffline(4096, to: chunk)
            guard status == .success else { break }
            let channels = try #require(chunk.floatChannelData)
            for channel in 0 ..< Int(format.channelCount) {
                for frame in 0 ..< Int(chunk.frameLength) {
                    let sample = channels[channel][frame]
                    sums[channel] += sample * sample
                }
            }
            frames += Int(chunk.frameLength)
        }
        return sums.map { sqrtf($0 / Float(max(frames, 1))) }.reduce(0, +)
    }

    @discardableResult
    private func play(_ engine: WorldAudioEngine, category: AudioCategory) throws -> Int {
        try engine.playPositional(buffer: makeToneBuffer(), request: AudioPlayRequest(
            name: "tone-\(category.rawValue)",
            category: category,
            worldPosition: SIMD3(2 * Self.oneMeterUnits, 0, 0)
        ))
    }

    private func effectiveGain(
        _ engine: WorldAudioEngine, category: AudioCategory
    ) throws -> Float {
        let source = try #require(engine.sources.first { $0.category == category })
        return engine.effectiveGain(of: source)
    }

    /// The rendered proof: muting a category silences its source, while a
    /// source in another category keeps sounding at full level.
    @Test
    func mutingACategorySilencesOnlyThatCategory() throws {
        let muted = try makeRunningEngine()
        muted.setMuted(true, for: .effects)
        try play(muted, category: .effects)
        let mutedRMS = try renderRMS(muted)

        let other = try makeRunningEngine()
        other.setMuted(true, for: .effects)
        try play(other, category: .ambience)
        let otherRMS = try renderRMS(other)

        #expect(mutedRMS < 1e-4, "a muted category must be silent, got \(mutedRMS)")
        #expect(otherRMS > 1e-2, "an unmuted category must keep sounding, got \(otherRMS)")
    }

    /// Muting after a source started reaches the playing node, and the panel's
    /// reported effective gain follows.
    @Test
    func mutingAPlayingSourceAppliesImmediately() throws {
        let engine = try makeRunningEngine()
        try play(engine, category: .effects)
        let beforeMute = try effectiveGain(engine, category: .effects)
        #expect(abs(beforeMute - 1) < 1e-5)

        engine.setMuted(true, for: .effects)
        #expect(try effectiveGain(engine, category: .effects) == 0)
        let source = try #require(engine.sources.first)
        #expect(source.node.volume == 0)
        // The non-positional path carries the same factor at the submix.
        #expect(engine.categoryMixers[.effects]?.outputVolume == 0)
    }

    /// Solo silences every other category; clearing it restores them.
    @Test
    func soloSilencesOtherCategoriesAndClearingRestoresThem() throws {
        let engine = try makeRunningEngine()
        try play(engine, category: .music)
        try play(engine, category: .effects)

        engine.soloedCategory = .music
        let soloedGain = try effectiveGain(engine, category: .music)
        let suppressedGain = try effectiveGain(engine, category: .effects)
        #expect(abs(soloedGain - 1) < 1e-5)
        #expect(suppressedGain == 0)
        #expect(engine.categoryMixers[.effects]?.outputVolume == 0)

        engine.soloedCategory = nil
        let restoredMusic = try effectiveGain(engine, category: .music)
        let restoredEffects = try effectiveGain(engine, category: .effects)
        #expect(abs(restoredMusic - 1) < 1e-5)
        #expect(abs(restoredEffects - 1) < 1e-5)
    }

    /// A soloed category renders while another category is silent, measured on
    /// the rendered mix rather than the snapshot.
    @Test
    func soloedCategoryStillRenders() throws {
        let soloed = try makeRunningEngine()
        soloed.soloedCategory = .music
        try play(soloed, category: .music)
        let soloedRMS = try renderRMS(soloed)

        let suppressed = try makeRunningEngine()
        suppressed.soloedCategory = .music
        try play(suppressed, category: .effects)
        let suppressedRMS = try renderRMS(suppressed)

        #expect(soloedRMS > 1e-2, "the soloed category must sound, got \(soloedRMS)")
        #expect(
            suppressedRMS < 1e-4,
            "a non-soloed category must be silent, got \(suppressedRMS)"
        )
    }

    /// Precedence: solo overrides nothing about mute. Soloing an explicitly
    /// muted category leaves it silent.
    @Test
    func soloDoesNotUnmuteTheSoloedCategory() throws {
        let engine = try makeRunningEngine()
        engine.setMuted(true, for: .music)
        engine.soloedCategory = .music
        try play(engine, category: .music)
        #expect(try effectiveGain(engine, category: .music) == 0)
        #expect(engine.isMuted(.music))

        engine.setMuted(false, for: .music)
        let unmutedGain = try effectiveGain(engine, category: .music)
        #expect(abs(unmutedGain - 1) < 1e-5)
    }

    /// Mute is state of its own: it does not touch the category volume, so
    /// unmuting restores the level the slider was left at.
    @Test
    func unmutingRestoresThePriorVolume() throws {
        let engine = try makeRunningEngine()
        engine.setVolume(0.25, for: .effects)
        try play(engine, category: .effects)
        engine.setMuted(true, for: .effects)
        #expect(engine.volume(for: .effects) == 0.25)
        #expect(try effectiveGain(engine, category: .effects) == 0)

        engine.setMuted(false, for: .effects)
        let unmutedGain = try effectiveGain(engine, category: .effects)
        #expect(abs(unmutedGain - 0.25) < 1e-5)
    }

    /// A source started while its category is muted comes up silent, and
    /// unmuting brings it in.
    @Test
    func sourceStartedWhileMutedIsSilentUntilUnmuted() throws {
        let engine = try makeRunningEngine()
        engine.setMuted(true, for: .ambience)
        try play(engine, category: .ambience)
        let source = try #require(engine.sources.first)
        #expect(source.node.volume == 0)

        engine.setMuted(false, for: .ambience)
        #expect(abs(source.node.volume - 1) < 1e-5)
    }
}
