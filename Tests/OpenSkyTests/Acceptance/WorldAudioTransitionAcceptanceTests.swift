// Door SFX, ambience, and music react together to one exterior -> interior ->
// exterior sequence through the real `CellStreamer` and an offline audio
// engine. Interior ambience arrives only through `apply(transition:)`. The
// interaction comes through `onInteraction`, not a raycast.

import FormatsAudioTesting
@testable import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldTesting
import simd
import TagsTesting
import Testing

@Suite(.tags(.acceptance))
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
            streamer = CellStreamerFixture.makeStreamer(runner: runner)
            // Exactly the three subscriptions the game controller makes.
            streamer.onAmbienceContextChanged = { soundDirector.handleAmbienceContext($0) }
            streamer.onMusicContextChanged = { musicDirector.handleMusicContext($0) }
            streamer.onInteraction.add { soundDirector.handleInteraction($0) }
        }

        /// Step 1: the center cell arrives carrying one region and one cell
        /// music type, so the bed starts and the exploration playlist plays.
        func arriveInTheExterior() throws {
            streamer.update(cameraPosition: CellStreamerFixture.center)
            runner.complete(
                CellStreamerFixture.coordinate(0, 0), with: .success(Self.exteriorScene)
            )
            streamer.update(cameraPosition: CellStreamerFixture.center)

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
            #expect(streamer.onInteraction.handlerCount == 1)
            streamer.onInteraction(event)

            #expect(sound.lastSFXDescription == "sound\\fx\\dor\\doorwoodopen.xwm")
            #expect(sound.lastSFXError == nil)
            #expect(
                names(of: .effects).filter { $0.contains("\\dor\\") }
                    == ["sound\\fx\\dor\\doorwoodopen.xwm"]
            )
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
            names(of: .effects).filter { $0.contains("\\amb\\") }
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
            CellStreamerFixture.cellScene(
                location: .exterior(CellStreamerFixture.coordinate(0, 0)),
                regions: [FormID(exteriorRegion)],
                musicType: explorationMusic
            )
        }

        private static var interiorScene: CellScene {
            CellStreamerFixture.cellScene(
                location: .interior(interiorCell),
                acousticSpace: FormID(interiorAcousticSpace),
                musicType: interiorMusic
            )
        }
    }
}
