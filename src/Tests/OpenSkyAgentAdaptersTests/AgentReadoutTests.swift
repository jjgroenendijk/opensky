import Foundation

// The readouts that read a sibling part answer from the fakes: the menu state with its
// screens, the player state with its cell, weather, and health cues, the dragon flights,
// and the movie and loading screen commands.

import OpenSkyActorsInterface
import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct AgentReadoutTests {
    private let host = AgentHost()
    private let world: AgentWorldAdapter

    init() {
        host.fakeMovies.readout = MoviePlaybackReadout(loading: false, interruptible: true)
        host.fakeMapMenu.snapshot = MapMenuSnapshot(
            selected: nil, cameraHeight: nil, questTargets: [], lastResult: nil
        )
        world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    private func object(_ json: AgentJSON) -> [String: AgentJSON] {
        guard case let .object(fields) = json else { return [:] }
        return fields
    }

    @Test func theCloudStateListsEachMovingLayerWithItsOffset() {
        var drift = CloudDrift()
        let velocities: [SIMD2<Float>] = [.zero, SIMD2(0.01, -0.02)]
        drift.advance(seconds: 10, velocities: velocities)
        let state = object(AgentFrameReadoutAdapter.cloudState(
            velocities: velocities, drift: drift, drawnLayers: 2
        ))
        #expect(state["drawnLayers"] == .init(2))
        guard case let .array(layers) = state["layers"], let layer = layers.first else {
            Issue.record("no moving layer")
            return
        }
        #expect(layers.count == 1)
        #expect(object(layer)["layer"] == .init(1))
        #expect(object(layer)["velocity"] == .init(SIMD2<Float>(0.01, -0.02)))
        #expect(object(layer)["offset"] == .init(drift.offset(layer: 1)))
    }

    @Test func theMenuStateShowsEachScreen() throws {
        let state = try object(world.query(.menu))
        for screen in ["hud", "loading", "movie", "bink", "titles", "map"] {
            #expect(state[screen] != nil, "\(screen)")
        }
    }

    @Test func anOpenTweenMenuShowsItsHighlight() throws {
        let tween = FakeTweenMenuPort()
        tween.isOpen = true
        tween.highlighted = .magic
        tween.showsLevelUp = true
        host.fakeMenuScreens.tween = tween
        host.fakeMenuMode.topMenu = MenuIdentifier("TweenMenu")
        let state = try object(world.query(.menu))
        let readout = object(state["tween"] ?? .null)
        #expect(readout["highlighted"] == .string("magic"))
        #expect(readout["levelUp"] == .bool(true))
    }

    @Test func aStartedMovieAndAForcedScreenAnswerTheirState() throws {
        host.fakeMovies.playResult = true
        host.fakeLoadingScreens.forceResult = true
        let movie = try world.perform(.playBink(file: "Intro.bik", interruptible: true))
        let screen = try world.perform(.loadScreen("SomeLoadScreen"))
        guard
            case let .done(.success(movieState)) = movie,
            case let .done(.success(screenState)) = screen
        else {
            Issue.record("a command did not finish")
            return
        }
        #expect(object(movieState)["bink"] != nil)
        #expect(object(screenState)["loading"] != nil)
    }

    @Test func theTitleMenuRowsComeFromTheMovieOnceItLoads() {
        host.fakeMenuMode.topMenu = .titleMenu
        let movie = TitleMenuMovieSnapshot(isLoaded: true, rows: ["Continue"], selectedIndex: 0)
        host.fakeTitleMenu.snapshotValue = TitleMenuSnapshot(
            rows: ["New"], selectedIndex: 0, isLoadPageOpen: false, lastResult: nil
        )
        #expect(world.menuReadout.menuRows()?.rows == ["New"])
        host.fakeTitleMenu.snapshotValue = TitleMenuSnapshot(
            rows: ["New"], selectedIndex: 0, isLoadPageOpen: false, lastResult: nil, movie: movie
        )
        #expect(world.menuReadout.menuRows()?.rows == ["Continue"])
    }

    @Test func eachFlyingDragonIsListed() throws {
        host.fakeDragonFlightWorld.flyingStates = [.generated(7): 1]
        let state = try object(world.query(.flight(reference: nil)))
        guard case let .array(flying)? = state["flying"] else {
            Issue.record("no flying list")
            return
        }
        #expect(flying.count == 1)
    }

    @Test func theClothStateListsEachCape() throws {
        host.clothReadout = ClothReadout(
            isEnabled: true, steppedCount: 1,
            capes: [ClothCapeReadout(
                actor: FormID(0x14),
                bone: "NPC Spine2 [Spn2]",
                miss: .noPlayerPose
            )]
        )
        let state = try object(world.query(.cloth))
        #expect(state["enabled"] == .bool(true))
        #expect(state["stepped"] == AgentJSON(1))
        guard case let .array(capes)? = state["capes"] else {
            Issue.record("no cape list")
            return
        }
        #expect(capes.count == 1)
        #expect(capes.first?.objectValue?["miss"] == .string("noPlayerPose"))
    }

    @Test func thePlayerStateReadsItsSiblingParts() throws {
        let session = FakeGameSessionPort()
        session.freeFlyCameraValue = FreeFlyCamera(position: [1, 2, 3], yaw: 0, pitch: 0)
        session.movementModeValue = .walk
        host.gameSession = session
        host.fakeControllerRumble.soundMotors = .silent
        host.fakeRagdoll.deathSettings = .vanilla
        let death = FakePlayerDeathPort()
        death.phase = .alive
        host.fakeRagdoll.playerDeath = death
        host.fakePlayer.firstPersonSnapshot = .unavailable
        host.fakeEffects.recordsValue = EffectRecordStore(plugins: [])
        let state = try object(world.query(.player))
        #expect(state["cell"] != nil)
        #expect(state["healthCues"] != nil)
    }

    @Test func theSoundsReadListsPlayingAndStartedSounds() throws {
        let loop = try PlayingLoopSession()
        loop.engine.releaseSource(id: loop.id)
        host.gameSession = loop.session
        let state = try object(world.query(.sounds))
        guard
            case let .array(playing)? = state["playing"],
            case let .array(started)? = state["started"]
        else {
            Issue.record("no sound lists")
            return
        }
        #expect(object(playing[0])["released"] == .bool(true))
        #expect(object(started[0])["file"] == .string("loop.wav"))
    }

    @Test func anActorInRangeIsListed() throws {
        let session = FakeGameSessionPort()
        session.freeFlyCameraValue = FreeFlyCamera(position: [0, 0, 0], yaw: 0, pitch: 0)
        host.gameSession = session
        host.fakeFactions.hostilityResult = .neutral
        host.fakeEffects.skinDecalsValue = SkinDecalRuntime()
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: .generated(9), feet: [10, 0, 0], name: "guard")
        ]
        let state = try object(world.query(.actors(radius: 1024)))
        guard case let .array(rows)? = state["actors"] else {
            Issue.record("no actor list")
            return
        }
        #expect(rows.count == 1)
    }
}
