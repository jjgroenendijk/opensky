// M9 acceptance, synthetic half of the "door SFX, ambience, and music
// transitioning between interior and exterior" sentence (issue #157): one
// exterior -> interior -> exterior sequence driven through the real
// `CellStreamer`, with the real sound and music directors subscribed to its
// callbacks and a real (offline-rendering) audio engine underneath. All three
// subsystems must react to the same transition.
//
// This also closes the coverage gap `CellStreamerAmbienceTests` writes down: the
// exterior-center path never flips to interior on its own, so interior ambience
// only ever arrives through `apply(transition:)`, which is exactly what this
// file exercises.
//
// Everything is synthetic and built in code (ESM plugins through `ESMFixture`,
// audio payloads through `XWMFixture`); no game data and no output device are
// involved. The interaction event is delivered through the streamer's own
// `onInteraction` seam rather than a raycast, because a view-ray hit needs
// collision geometry that says nothing about audio.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct WorldAudioTransitionAcceptanceTests {
    /// The full sequence: an exterior cell arrives with a region bed and an
    /// exploration playlist, a door is used and plays its activation SFX, the
    /// door transition swaps in an interior whose acoustic space supplies a new
    /// bed and whose cell music switches the state to interior, and the paired
    /// transition back restores the exterior bed and playlist.
    @Test
    func oneTransitionSequenceDrivesSFXAmbienceAndMusic() throws {
        let stage = try Stage()

        try stage.arriveInTheExterior()
        try stage.useTheDoor()
        try stage.enterTheInterior()
        try stage.returnToTheExterior()
    }

    /// One wired world: streamer, both directors, and the offline engine they
    /// share, plus the synthetic records they resolve against.
    @MainActor
    private final class Stage {
        let engine: WorldAudioEngine
        let sound: WorldAudioSoundDirector
        let music: WorldMusicDirector
        let streamer: CellStreamer
        let runner = ManualCellBuildRunner()

        /// SNDR descriptors: the exterior region bed, the interior acoustic
        /// space's ambient sound, and the door's activation sound.
        static let exteriorAmbience: UInt32 = 0xA01
        static let interiorAmbience: UInt32 = 0xA02
        static let doorActivation: UInt32 = 0xA03
        static let exteriorRegion: UInt32 = 0x100
        static let interiorAcousticSpace: UInt32 = 0x200
        static let interiorCell = FormID(0x138CA)
        /// MUSC ids from `MusicFixture.makeDefaultStore()`: the cycling
        /// exploration playlist and the town one.
        static let explorationMusic = FormID(0x20)
        static let interiorMusic = FormID(0x30)

        init() throws {
            engine = try WorldAudioDirectorFixture.makeRunningEngine()
            let soundStore = TransitionAudioFixture.makeSoundStore(descriptors: [
                (Self.exteriorAmbience, "sound\\fx\\amb\\exterior.xwm"),
                (Self.interiorAmbience, "sound\\fx\\amb\\interior.xwm"),
                (Self.doorActivation, "sound\\fx\\dor\\doorwoodopen.xwm")
            ])
            let weatherStore = WorldAudioDirectorFixture.makeWeatherStore(regions: [
                WorldAudioDirectorFixture.Region(
                    id: Self.exteriorRegion,
                    sounds: [WorldAudioDirectorFixture.Sound(
                        sound: Self.exteriorAmbience, flags: 0, chance: 1
                    )]
                )
            ])
            let soundDirector = WorldAudioSoundDirector(
                engine: engine,
                soundStore: soundStore,
                weatherStore: weatherStore,
                aspcStore: TransitionAudioFixture.makeAcousticSpaceStore(
                    id: Self.interiorAcousticSpace, ambientSound: Self.interiorAmbience
                ),
                fileLoader: { _ in XWMFixture.file(packetCount: 2) }
            )
            let musicDirector = MusicDirectorFixture.makeDirector(
                engine: engine, weatherStore: weatherStore
            )
            sound = soundDirector
            music = musicDirector
            streamer = CellStreamerTests.makeStreamer(runner: runner)
            // Exactly the three subscriptions the game controller makes.
            streamer.onAmbienceContextChanged = { soundDirector.handleAmbienceContext($0) }
            streamer.onMusicContextChanged = { musicDirector.handleMusicContext($0) }
            streamer.onInteraction = { soundDirector.handleInteraction($0) }
        }

        /// Step 1: the center cell arrives carrying one region and one cell
        /// music type, so the bed starts and the exploration playlist plays.
        func arriveInTheExterior() throws {
            streamer.update(cameraPosition: CellStreamerTests.center)
            runner.complete(
                CellStreamerTests.coordinate(0, 0), with: .success(Self.exteriorScene)
            )
            streamer.update(cameraPosition: CellStreamerTests.center)

            #expect(sound.currentAmbienceDescription != "none")
            #expect(ambienceNames == ["sound\\fx\\amb\\exterior.xwm"])
            #expect(music.currentStateName == "exploration")
            #expect(music.currentTrackName != nil)
        }

        /// Step 2: using the door plays its activation sound as a one-shot
        /// effect, alongside the bed and the music that are already sounding.
        func useTheDoor() throws {
            let event = WorldAudioDirectorFixture.makeInteractionEvent(
                sounds: ModelBase.Sounds(
                    activation: FormID(Self.doorActivation), close: nil, loop: nil
                )
            )
            let handler = try #require(streamer.onInteraction)
            handler(event)

            #expect(sound.lastSFXDescription == "sound\\fx\\dor\\doorwoodopen.xwm")
            #expect(sound.lastSFXError == nil)
            #expect(names(of: .effects) == ["sound\\fx\\dor\\doorwoodopen.xwm"])
            // The one-shot does not disturb the bed or the music.
            #expect(ambienceNames == ["sound\\fx\\amb\\exterior.xwm"])
            #expect(music.currentStateName == "exploration")
        }

        /// Step 3: the door transition swaps in the interior. The streamer
        /// re-emits both contexts, so the bed swaps to the acoustic space's
        /// sound and the music state becomes interior.
        func enterTheInterior() throws {
            let exteriorTrack = music.currentTrackName
            streamer.apply(transition: Self.transition(to: Self.interiorScene))

            #expect(ambienceNames == ["sound\\fx\\amb\\interior.xwm"])
            #expect(music.currentStateName == "interior")
            let interiorTrack = try #require(music.currentTrackName)
            #expect(interiorTrack != exteriorTrack, "the interior playlist is a different one")
        }

        /// Step 4: the paired door leads back outside, and both the bed and the
        /// playlist return to what the exterior cell selects.
        func returnToTheExterior() throws {
            streamer.apply(transition: Self.transition(to: Self.exteriorScene))

            #expect(ambienceNames == ["sound\\fx\\amb\\exterior.xwm"])
            #expect(music.currentStateName == "exploration")
            #expect(music.currentTrackName != nil)
        }

        /// Names of the engine's live ambience sources — what is audible now,
        /// not what the director wanted.
        private var ambienceNames: [String] {
            names(of: .ambience)
        }

        private func names(of category: AudioCategory) -> [String] {
            engine.sources.filter { $0.category == category }.map(\.name)
        }

        private static func transition(to scene: CellScene) -> DoorTransition {
            DoorTransition(
                sourceDoor: FormID(0x10),
                destinationDoor: FormID(0x20),
                destinationPlacement: PlacedReference.Placement(
                    position: SIMD3(100, 200, 300), rotation: .zero
                ),
                scene: scene
            )
        }

        private static var exteriorScene: CellScene {
            CellStreamerTests.cellScene(
                location: .exterior(CellStreamerTests.coordinate(0, 0)),
                regions: [FormID(exteriorRegion)],
                musicType: explorationMusic
            )
        }

        private static var interiorScene: CellScene {
            CellStreamerTests.cellScene(
                location: .interior(interiorCell),
                acousticSpace: FormID(interiorAcousticSpace),
                musicType: interiorMusic
            )
        }
    }
}

/// Synthetic plugins this suite needs beyond the shared audio fixtures: a
/// multi-descriptor SNDR store and a one-record ASPC store.
@MainActor
enum TransitionAudioFixture {
    /// One SNDR per entry, each naming a single ANAM track. Sound references
    /// resolve straight to SNDR (`resolveAny`), which is what vanilla door and
    /// region records do.
    static func makeSoundStore(descriptors: [(id: UInt32, track: String)]) -> SoundRecordStore {
        var bytes = Data()
        for descriptor in descriptors {
            let fields = ESMFixture.field("ANAM", ESMFixture.zstring(descriptor.track))
            bytes += ESMFixture.record("SNDR", formID: descriptor.id, data: fields)
        }
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup("SNDR", contents: bytes)
        do {
            return try SoundRecordStore(file: ESMFile(data: plugin))
        } catch {
            preconditionFailure("synthetic fixture failed: \(error)")
        }
    }

    /// One ASPC whose SNAM names the interior's direct ambient sound.
    static func makeAcousticSpaceStore(id: UInt32, ambientSound: UInt32) -> AcousticSpaceStore {
        var snam = Data()
        snam.appendUInt32(ambientSound)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Aspc\(id)"))
            + ESMFixture.field("SNAM", snam)
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup(
            "ASPC", contents: ESMFixture.record("ASPC", formID: id, data: fields)
        )
        do {
            return try AcousticSpaceStore(file: ESMFile(data: plugin))
        } catch {
            preconditionFailure("synthetic fixture failed: \(error)")
        }
    }
}
