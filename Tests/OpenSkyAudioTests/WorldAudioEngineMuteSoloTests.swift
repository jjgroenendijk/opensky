// Per-category mute and solo under offline rendering (docs/engine/audio.md): a
// muted category has zero gain, a solo silences the others, both filters must
// pass, and neither changes the category volume.

import AVFAudio
@testable import OpenSkyAudio
import simd
import Testing

@MainActor
struct WorldAudioEngineMuteSoloTests {
    /// ~1 m in native units.
    private static let oneMeterUnits: Float = 1 / AudioSpace.metersPerUnit

    private func renderRMS(_ engine: WorldAudioEngine) throws -> Float {
        try OfflineAudioFixture.channelRMS(engine).reduce(0, +)
    }

    @discardableResult
    private func play(_ engine: WorldAudioEngine, category: AudioCategory) throws -> Int {
        try engine.playPositional(
            buffer: OfflineAudioFixture.makeToneBuffer(seconds: 0.25),
            request: AudioPlayRequest(
                name: "tone-\(category.rawValue)",
                category: category,
                worldPosition: SIMD3(2 * Self.oneMeterUnits, 0, 0)
            )
        )
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
        let muted = try OfflineAudioFixture.makeRunningEngine()
        muted.setMuted(true, for: .effects)
        try play(muted, category: .effects)
        let mutedRMS = try renderRMS(muted)

        let other = try OfflineAudioFixture.makeRunningEngine()
        other.setMuted(true, for: .effects)
        try play(other, category: .voice)
        let otherRMS = try renderRMS(other)

        #expect(mutedRMS < 1e-4, "a muted category must be silent, got \(mutedRMS)")
        #expect(otherRMS > 1e-2, "an unmuted category must keep sounding, got \(otherRMS)")
    }

    /// Muting after a source started reaches the playing node, and the panel's
    /// reported effective gain follows.
    @Test
    func mutingAPlayingSourceAppliesImmediately() throws {
        let engine = try OfflineAudioFixture.makeRunningEngine()
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
        let engine = try OfflineAudioFixture.makeRunningEngine()
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
        let soloed = try OfflineAudioFixture.makeRunningEngine()
        soloed.soloedCategory = .music
        try play(soloed, category: .music)
        let soloedRMS = try renderRMS(soloed)

        let suppressed = try OfflineAudioFixture.makeRunningEngine()
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
        let engine = try OfflineAudioFixture.makeRunningEngine()
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
        let engine = try OfflineAudioFixture.makeRunningEngine()
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
        let engine = try OfflineAudioFixture.makeRunningEngine()
        engine.setMuted(true, for: .voice)
        try play(engine, category: .voice)
        let source = try #require(engine.sources.first)
        #expect(source.node.volume == 0)

        engine.setMuted(false, for: .voice)
        #expect(abs(source.node.volume - 1) < 1e-5)
    }
}
