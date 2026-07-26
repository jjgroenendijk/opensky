// Deterministic coverage for the per-source gain ramps a music crossfade is
// built from (docs/engine/audio.md). Ramps advance from explicit deltas, never
// a wall clock, so these tests need no sleeping and no output device. Shared
// offline fixtures live in WorldAudioEngineNonPositionalTests.swift.

import AVFAudio
@testable import opensky
import simd
import Testing

@MainActor
struct WorldAudioEngineFadeTests {
    @Test
    func fadeReachesItsTargetOverTheExpectedAdvances() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        let id = try MusicAudioFixture.playMusic(engine)
        #expect(engine.fadeSource(id: id, to: 0.5, overSeconds: 1))
        for _ in 0 ..< 30 {
            engine.advanceFades(deltaTime: 1 / 60)
        }
        let half = try #require(engine.fadeGain(of: id))
        #expect(abs(half - 0.75) < 0.02, "half way should be ~0.75, got \(half)")
        #expect(engine.isFading(id: id))
        for _ in 0 ..< 30 {
            engine.advanceFades(deltaTime: 1 / 60)
        }
        #expect(try abs(#require(engine.fadeGain(of: id)) - 0.5) < 1e-5)
        #expect(!engine.isFading(id: id), "a completed ramp must clear itself")
    }

    @Test
    func fadeInRaisesGainFromSilence() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        let id = try MusicAudioFixture.playMusic(engine)
        engine.fadeSource(id: id, to: 0, overSeconds: 0)
        #expect(try #require(engine.fadeGain(of: id)) == 0)
        engine.fadeSource(id: id, to: 1, overSeconds: 0.5)
        for _ in 0 ..< 30 {
            engine.advanceFades(deltaTime: 1 / 60)
        }
        #expect(try abs(#require(engine.fadeGain(of: id)) - 1) < 1e-5)
    }

    @Test
    func fadeOutAndStopRetiresTheSource() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        let id = try MusicAudioFixture.playMusic(engine)
        #expect(engine.fadeOutAndStopSource(id: id, overSeconds: 0.5))
        engine.advanceFades(deltaTime: 0.25)
        #expect(engine.sources.contains { $0.id == id }, "must still play mid-fade")
        #expect(try abs(#require(engine.fadeGain(of: id)) - 0.5) < 0.01)
        engine.advanceFades(deltaTime: 0.25)
        #expect(engine.sources.isEmpty, "a completed fade-out must retire the source")
    }

    @Test
    func zeroDurationFadeOutStopsImmediately() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        let id = try MusicAudioFixture.playMusic(engine)
        #expect(engine.fadeOutAndStopSource(id: id, overSeconds: 0))
        #expect(engine.sources.isEmpty)
        #expect(!engine.fadeSource(id: id, to: 1, overSeconds: 1), "unknown id returns false")
    }

    /// A second fade mid-ramp restarts from the gain the source is at, so the
    /// audible level never jumps.
    @Test
    func secondFadeStartsFromTheCurrentGain() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        let id = try MusicAudioFixture.playMusic(engine)
        engine.fadeSource(id: id, to: 0, overSeconds: 1)
        engine.advanceFades(deltaTime: 0.5)
        #expect(try abs(#require(engine.fadeGain(of: id)) - 0.5) < 0.01)
        engine.fadeSource(id: id, to: 1, overSeconds: 1)
        #expect(try abs(#require(engine.fadeGain(of: id)) - 0.5) < 0.01, "no jump on retarget")
        engine.advanceFades(deltaTime: 0.5)
        #expect(try abs(#require(engine.fadeGain(of: id)) - 0.75) < 0.02)
    }

    /// The regression that matters: moving a volume slider mid-crossfade must
    /// not stomp the ramp.
    @Test
    func volumeChangesDoNotStompAnInFlightFade() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        let id = try MusicAudioFixture.playMusic(engine)
        let source = try #require(engine.sources.first)
        engine.fadeSource(id: id, to: 0, overSeconds: 1)
        engine.advanceFades(deltaTime: 0.5)
        engine.setVolume(0.5, for: .music)
        engine.masterVolume = 0.5
        #expect(abs(source.fadeGain - 0.5) < 0.01, "the ramp must survive a slider move")
        #expect(abs(source.node.volume - 0.5) < 0.01, "node gain keeps the fade factor")
        #expect(engine.isFading(id: id))
        engine.advanceFades(deltaTime: 0.5)
        #expect(try #require(engine.fadeGain(of: id)) == 0)
    }

    /// A positional source fades the same way, with the category factor still
    /// at its node.
    @Test
    func positionalSourcesFadeToo() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        try MusicAudioFixture.playEffect(engine, name: "effect")
        let source = try #require(engine.sources.first)
        engine.setVolume(0.5, for: .effects)
        engine.fadeSource(id: source.id, to: 0.5, overSeconds: 1)
        engine.advanceFades(deltaTime: 1)
        #expect(abs(source.node.volume - 0.25) < 1e-5, "category x fade at the node")
    }

    @Test
    func effectiveGainAndSnapshotReportTheFade() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        let id = try MusicAudioFixture.playMusic(engine, gain: 0.8)
        engine.fadeSource(id: id, to: 0.5, overSeconds: 0)
        let source = try #require(engine.sources.first)
        #expect(abs(engine.effectiveGain(of: source) - 0.4) < 1e-5)
        engine.fadeSource(id: id, to: 1, overSeconds: 1)
        let row = try #require(engine.statsSnapshot().sources.first)
        #expect(!row.isPositional)
        #expect(row.distanceMeters == 0)
        #expect(abs(row.fadeGain - 0.5) < 1e-5)
        #expect(row.isFading)
        #expect(abs(row.effectiveGain - 0.4) < 1e-5)
    }

    /// The tick is the production entry point: it advances fades with the
    /// renderer's frame delta, and a zero delta (paused world) freezes them.
    @Test
    func tickAdvancesFadesAndAZeroDeltaFreezesThem() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        let id = try MusicAudioFixture.playMusic(engine)
        engine.fadeSource(id: id, to: 0, overSeconds: 1)
        let cell = CellCoordinate(x: 0, y: 0)
        engine.tick(listenerCell: cell, deltaTime: 0.25)
        #expect(try abs(#require(engine.fadeGain(of: id)) - 0.75) < 0.01)
        for _ in 0 ..< 10 {
            engine.tick(listenerCell: cell, deltaTime: 0)
        }
        #expect(try abs(#require(engine.fadeGain(of: id)) - 0.75) < 0.01, "paused must freeze")
        engine.tick(listenerCell: cell, deltaTime: 0.75)
        #expect(try #require(engine.fadeGain(of: id)) == 0)
    }

    /// A crossfade is two ramps in flight at once: one out-and-stop, one in.
    @Test
    func crossfadeSwapsTwoSources() throws {
        let engine = try MusicAudioFixture.makeRunningEngine()
        let outgoing = try MusicAudioFixture.playMusic(engine, name: "outgoing")
        let incoming = try MusicAudioFixture.playMusic(engine, name: "incoming", gain: 1)
        engine.fadeSource(id: incoming, to: 0, overSeconds: 0)
        engine.fadeOutAndStopSource(id: outgoing, overSeconds: 2)
        engine.fadeSource(id: incoming, to: 1, overSeconds: 2)
        for _ in 0 ..< 60 {
            engine.tick(listenerCell: CellCoordinate(x: 0, y: 0), deltaTime: 1 / 60)
        }
        #expect(try abs(#require(engine.fadeGain(of: outgoing)) - 0.5) < 0.02)
        #expect(try abs(#require(engine.fadeGain(of: incoming)) - 0.5) < 0.02)
        for _ in 0 ..< 60 {
            engine.tick(listenerCell: CellCoordinate(x: 0, y: 0), deltaTime: 1 / 60)
        }
        #expect(engine.sources.map(\.name) == ["incoming"])
        #expect(try #require(engine.fadeGain(of: incoming)) == 1)
    }
}
