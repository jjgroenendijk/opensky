// Sounds a clip annotation names by `SNDR` editor ID: a one-shot plays and is not
// tracked, a loop plays until the same source stops it.

@testable import OpenSkyAudio
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import Testing

@MainActor
struct WorldAudioSoundDirectorAnimationTests {
    private typealias Fixture = WorldAudioDirectorFixture
    private let source = ReferenceKey.plugin(name: "test.esp", objectID: 0x10)

    private func director(
        engine: WorldAudioEngine, loops: Bool
    ) -> WorldAudioSoundDirector {
        Fixture.makeDirector(
            engine: engine,
            soundStore: Fixture.makeSoundStore(
                soundID: 0xAAA, descriptorID: 0xBBB, tracks: ["fx/clap.xwm"],
                loops: loops, editorID: "TestClap"
            )
        )
    }

    @Test func aOneShotPlaysByEditorIDInAnyCase() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = director(engine: engine, loops: false)
        #expect(director.playAnimationSound(
            editorID: "testclap", source: source, at: SIMD3(1, 0, 0)
        ))
        #expect(engine.sources.count == 1)
        #expect(engine.sources.first?.loops == false)
        #expect(director.animationLoopCount == 0)
    }

    @Test func aLoopStopsWhenItsSourceStopsIt() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = director(engine: engine, loops: true)
        director.playAnimationSound(editorID: "TestClap", source: source, at: .zero)
        #expect(director.animationLoopCount == 1)
        #expect(engine.sources.first?.loops == true)

        let other = ReferenceKey.plugin(name: "test.esp", objectID: 0x11)
        director.stopAnimationSound(editorID: "TestClap", source: other)
        #expect(director.animationLoopCount == 1, "another source's stop leaves it")

        director.stopAnimationSound(editorID: "TESTCLAP", source: source)
        #expect(director.animationLoopCount == 0)
        #expect(engine.sources.isEmpty)
    }

    @Test func anUnknownEditorIDPlaysNothing() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = director(engine: engine, loops: false)
        #expect(!director.playAnimationSound(editorID: "TestOther", source: source, at: .zero))
        #expect(engine.sources.isEmpty)
        #expect(director.lastSFXError == "no SNDR TestOther")
    }
}
