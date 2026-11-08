// Papyrus `Sound.Play` over the director: a script passes a `SOUN`, which names
// its `SNDR`, and a looping descriptor plays until `StopInstance`.

@testable import OpenSkyAudio
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import Testing

@MainActor
struct WorldAudioSoundDirectorScriptTests {
    private typealias Fixture = WorldAudioDirectorFixture

    private func director(engine: WorldAudioEngine) -> WorldAudioSoundDirector {
        Fixture.makeDirector(
            engine: engine,
            soundStore: Fixture.makeSoundStore(
                soundID: 0xAAA, descriptorID: 0xBBB, tracks: ["fx/cart.xwm"], loops: true
            )
        )
    }

    @Test func aSoundMarkerLoopsUntilItsInstanceStops() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = director(engine: engine)
        let instance = director.playScriptSound(formID: FormID(0xAAA), at: SIMD3(1, 0, 0))
        #expect(instance != 0)
        #expect(engine.sources.count == 1)
        #expect(engine.sources.first?.loops == true)

        director.stopScriptSound(instance)
        #expect(engine.sources.isEmpty)
    }

    @Test func aDescriptorPlaysDirectly() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = director(engine: engine)
        #expect(director.playScriptSound(formID: FormID(0xBBB), at: .zero) != 0)
        #expect(engine.sources.count == 1)
    }

    @Test func anUnknownFormPlaysNothing() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = director(engine: engine)
        #expect(director.playScriptSound(formID: FormID(0xDDD), at: .zero) == 0)
        #expect(engine.sources.isEmpty)
    }
}
