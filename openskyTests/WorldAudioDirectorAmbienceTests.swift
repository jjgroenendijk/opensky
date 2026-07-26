// Ambience-bed behavior of WorldAudioSoundDirector over the offline-render
// engine: bed start and swap on context change, the World > Audio toggle
// retiring and restarting the bed live, looping bed sources, and the readout
// telling the truth about what is playing. See docs/engine/world-sfx.md.

@testable import opensky
import Testing

@MainActor
struct WorldAudioDirectorAmbienceTests {
    private typealias Fixture = WorldAudioDirectorFixture

    @Test func handleAmbienceStartsLoopsForNonEmptyBed() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeAmbienceDirector(engine: engine)

        director.handleAmbienceContext(Fixture.regionContext)

        #expect(engine.sources.count == 1)
        #expect(engine.sources.first?.category == .ambience)
    }

    @Test func handleAmbienceRetiresPreviousBedOnContextChange() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeAmbienceDirector(engine: engine)

        director.handleAmbienceContext(Fixture.regionContext)
        #expect(engine.sources.count == 1)

        // Same context: no-op (the resolved bed did not change).
        director.handleAmbienceContext(Fixture.regionContext)
        #expect(engine.sources.count == 1)

        // Empty context: retires the previous bed.
        director.handleAmbienceContext(AmbienceContext.empty)
        #expect(engine.sources.isEmpty)
    }

    @Test func handleAmbienceNoOpWhenDisabled() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeAmbienceDirector(engine: engine)
        director.ambienceEnabled = false

        director.handleAmbienceContext(Fixture.regionContext)

        #expect(engine.sources.isEmpty)
    }

    /// The panel checkbox must retire the playing bed the moment it is
    /// unticked, and restart it when it is ticked again.
    @Test func ambienceToggleRetiresAndRestartsBed() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeAmbienceDirector(engine: engine)

        director.handleAmbienceContext(Fixture.regionContext)
        #expect(engine.sources.count == 1)
        #expect(director.currentAmbienceDescription != "none")

        director.ambienceEnabled = false
        #expect(engine.sources.isEmpty, "unticking must retire the playing bed")
        #expect(director.currentAmbienceDescription == "none")

        director.ambienceEnabled = true
        #expect(engine.sources.count == 1, "re-ticking must restart the bed")
        #expect(engine.sources.first?.category == .ambience)
        #expect(director.currentAmbienceDescription != "none")
    }

    /// A context that arrives while ambience is off is remembered, so enabling
    /// starts that bed without waiting for the center cell to change.
    @Test func ambienceEnabledAfterContextStartsRememberedBed() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeAmbienceDirector(engine: engine)
        director.ambienceEnabled = false

        director.handleAmbienceContext(Fixture.regionContext)
        #expect(engine.sources.isEmpty)
        #expect(director.currentAmbienceDescription == "none")

        director.ambienceEnabled = true
        #expect(engine.sources.count == 1)
        #expect(director.currentAmbienceDescription != "none")
    }

    /// Bed sources start as loops, so the streamer rewinds at end of file
    /// instead of the engine retiring the bed after a single pass.
    @Test func ambienceSourcesAreStartedAsLoops() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeAmbienceDirector(engine: engine)

        director.handleAmbienceContext(Fixture.regionContext)

        let source = try #require(engine.sources.first)
        #expect(source.loops, "an ambience bed must be a looping source")
    }

    /// `WorldAudioEngine.stopSource(id:)` selectivity: retiring the bed leaves
    /// a concurrent one-shot effect playing.
    @Test func retiringAmbienceLeavesOneShotSFXAlive() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeAmbienceDirector(engine: engine)

        director.handleAmbienceContext(Fixture.regionContext)
        director.handleInteraction(Fixture.makeInteractionEvent(
            sounds: ModelBase.Sounds(activation: FormID(0xAAA), close: nil, loop: nil)
        ))
        #expect(engine.sources.count == 2)

        director.ambienceEnabled = false

        #expect(engine.sources.map(\.category) == [.effects])
        #expect(director.currentAmbienceDescription == "none")
    }

    /// The readout must not claim a bed the engine already retired on its own
    /// (FIFO eviction, cell purge, or a stream that ended).
    @Test func readoutReportsNoneAfterEngineRetiresTheBed() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeAmbienceDirector(engine: engine)

        director.handleAmbienceContext(Fixture.regionContext)
        #expect(director.currentAmbienceDescription != "none")

        engine.stopAllSources()

        #expect(director.currentAmbienceDescription == "none")
    }
}
