// Deterministic offline-render coverage for the world audio graph
// (docs/engine/audio.md): channel balance for a known source/listener pose,
// distance attenuation, the documented gain product, the FIFO source budget and
// the cell-unload purge. Uses AVAudioEngine manual offline rendering — no
// output device, no playback, no decode-queue timing.

import AVFAudio
@testable import OpenSkyAudio
@testable import OpenSkyFormatsCore
import simd
import Testing

@MainActor
struct WorldAudioEngineTests {
    /// ~1 m in native units.
    private static let oneMeterUnits: Float = 1 / AudioSpace.metersPerUnit

    private func play(
        _ engine: WorldAudioEngine, at worldPosition: SIMD3<Float>, name: String = "tone"
    ) throws {
        try engine.playPositional(
            buffer: OfflineAudioFixture.makeToneBuffer(seconds: 0.25),
            request: AudioPlayRequest(
                name: name, category: .effects, worldPosition: worldPosition
            )
        )
    }

    @Test
    func sourceToTheRightPansRight() throws {
        let engine = try OfflineAudioFixture.makeRunningEngine()
        // Listener at origin facing +X east; its right hand points -Y.
        engine.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        try play(engine, at: SIMD3(0, -2 * Self.oneMeterUnits, 0))
        let rms = try OfflineAudioFixture.channelRMS(engine)
        #expect(rms[1] > rms[0] * 4, "right \(rms[1]) should dominate left \(rms[0])")
    }

    @Test
    func sourceToTheLeftPansLeft() throws {
        let engine = try OfflineAudioFixture.makeRunningEngine()
        engine.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        try play(engine, at: SIMD3(0, 2 * Self.oneMeterUnits, 0))
        let rms = try OfflineAudioFixture.channelRMS(engine)
        #expect(rms[0] > rms[1] * 4, "left \(rms[0]) should dominate right \(rms[1])")
    }

    @Test
    func fartherSourcesAttenuate() throws {
        let near = try OfflineAudioFixture.makeRunningEngine()
        near.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        try play(near, at: SIMD3(2 * Self.oneMeterUnits, 0, 0))
        let nearRMS = try OfflineAudioFixture.channelRMS(near).reduce(0, +)

        let far = try OfflineAudioFixture.makeRunningEngine()
        far.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        try play(far, at: SIMD3(40 * Self.oneMeterUnits, 0, 0))
        let farRMS = try OfflineAudioFixture.channelRMS(far).reduce(0, +)

        #expect(nearRMS > farRMS * 4, "near \(nearRMS) vs far \(farRMS)")
    }

    /// The documented product: effective gain = master x category x source.
    @Test
    func categoryVolumeScalesOutput() throws {
        let loud = try OfflineAudioFixture.makeRunningEngine()
        loud.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        try play(loud, at: SIMD3(2 * Self.oneMeterUnits, 0, 0))
        let loudRMS = try OfflineAudioFixture.channelRMS(loud).reduce(0, +)

        let quiet = try OfflineAudioFixture.makeRunningEngine()
        quiet.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        quiet.setVolume(0.25, for: .effects)
        try play(quiet, at: SIMD3(2 * Self.oneMeterUnits, 0, 0))
        let quietRMS = try OfflineAudioFixture.channelRMS(quiet).reduce(0, +)

        let ratio = quietRMS / loudRMS
        #expect(abs(ratio - 0.25) < 0.05, "ratio \(ratio) should be ~0.25")
        let source = try #require(quiet.sources.first)
        #expect(abs(quiet.effectiveGain(of: source) - 0.25) < 1e-5)
    }

    @Test
    func masterVolumeZeroSilences() throws {
        let engine = try OfflineAudioFixture.makeRunningEngine()
        engine.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        engine.masterVolume = 0
        try play(engine, at: SIMD3(2 * Self.oneMeterUnits, 0, 0))
        let rms = try OfflineAudioFixture.channelRMS(engine).reduce(0, +)
        #expect(rms < 1e-4, "master 0 must silence the mix, got \(rms)")
    }

    /// Budget rule: at the cap, starting another source evicts the oldest
    /// (FIFO by start order).
    @Test
    func sourceCapEvictsOldestFirst() throws {
        let engine = try OfflineAudioFixture.makeRunningEngine()
        for index in 0 ..< (WorldAudioEngine.maxConcurrentSources + 1) {
            try play(engine, at: .zero, name: "source-\(index)")
        }
        #expect(engine.sources.count == WorldAudioEngine.maxConcurrentSources)
        let names = engine.sources.map(\.name)
        #expect(!names.contains("source-0"), "oldest source must be evicted")
        #expect(names.first == "source-1")
    }

    /// Cell-unload cleanup: sources beyond the purge radius stop on the tick.
    @Test
    func tickPurgesSourcesOutsideCellRadius() throws {
        let engine = try OfflineAudioFixture.makeRunningEngine()
        let cellSpan: Float = 4096
        try play(engine, at: .zero, name: "near")
        let farCells = Float(WorldAudioEngine.cellPurgeRadius + 2)
        try play(engine, at: SIMD3(farCells * cellSpan, 0, 0), name: "far")
        engine.tick(listenerCell: CellCoordinate(x: 0, y: 0))
        let names = engine.sources.map(\.name)
        #expect(names == ["near"], "far source must purge, got \(names)")
    }

    /// A looping request keeps producing audio past the end of its material,
    /// which is what an ambience bed needs; a one-shot falls silent.
    @Test
    func loopingSourceKeepsPlayingPastItsMaterial() throws {
        let looping = try OfflineAudioFixture.makeRunningEngine()
        looping.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        try playShortTone(looping, loops: true)
        // Skip the first render pass so the measured window lies past the end
        // of the 0.02 s buffer.
        _ = try OfflineAudioFixture.channelRMS(looping)
        let loopingRMS = try OfflineAudioFixture.channelRMS(looping).reduce(0, +)

        let oneShot = try OfflineAudioFixture.makeRunningEngine()
        oneShot.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        try playShortTone(oneShot, loops: false)
        _ = try OfflineAudioFixture.channelRMS(oneShot)
        let oneShotRMS = try OfflineAudioFixture.channelRMS(oneShot).reduce(0, +)

        #expect(oneShotRMS < 1e-4, "a one-shot must fall silent, got \(oneShotRMS)")
        #expect(loopingRMS > 1e-2, "a loop must keep sounding, got \(loopingRMS)")
    }

    private func playShortTone(_ engine: WorldAudioEngine, loops: Bool) throws {
        try engine.playPositional(
            buffer: OfflineAudioFixture.makeToneBuffer(seconds: 0.02),
            request: AudioPlayRequest(
                name: "tone",
                category: .voice,
                worldPosition: SIMD3(2 * Self.oneMeterUnits, 0, 0),
                loops: loops
            )
        )
    }

    @Test
    func snapshotReportsSourcesAndDistance() throws {
        let engine = try OfflineAudioFixture.makeRunningEngine()
        engine.updateListener(worldPosition: .zero, yaw: 0, pitch: 0)
        try play(engine, at: SIMD3(2 * Self.oneMeterUnits, 0, 0), name: "music\\test.xwm")
        let snapshot = engine.statsSnapshot()
        #expect(snapshot.enabled)
        #expect(snapshot.engineRunning)
        #expect(snapshot.sourceCap == WorldAudioEngine.maxConcurrentSources)
        let source = try #require(snapshot.sources.first)
        #expect(source.name == "music\\test.xwm")
        #expect(abs(source.distanceMeters - 2) < 0.01)
        #expect(abs(source.effectiveGain - 1) < 1e-5)
    }

    @Test
    func disabledEngineRefusesPlayback() throws {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: OfflineAudioFixture.sampleRate, channels: 2)
        )
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        #expect(throws: AudioEngineError.notRunning) {
            try engine.playPositional(
                buffer: OfflineAudioFixture.makeToneBuffer(),
                request: AudioPlayRequest(
                    name: "tone", category: .effects, worldPosition: .zero
                )
            )
        }
    }
}
