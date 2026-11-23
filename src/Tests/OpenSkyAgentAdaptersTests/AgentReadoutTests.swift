import Foundation

// The readouts that read a sibling part answer from the fakes: the menu state with its
// screens, the player state with its cell, weather, and health cues, the dragon flights,
// and the movie and loading screen commands.

import OpenSkyActorsInterface
import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyEngineTesting
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct AgentReadoutTests {
    let host = AgentHost()
    let world: AgentWorldAdapter

    init() {
        host.fakeMovies.readout = MoviePlaybackReadout(loading: false, interruptible: true)
        host.fakeMapMenu.snapshot = MapMenuSnapshot(
            selected: nil, cameraHeight: nil, questTargets: [], lastResult: nil
        )
        world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    func object(_ json: AgentJSON) -> [String: AgentJSON] {
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

    @Test func theStoryStateCountsEachEventAndListsTheNewest() throws {
        host.fakeStoryManager.firedCounts = ["QSTR": 2]
        host.fakeStoryManager.recentEvents = [.questStart(FormID(0x0100))]
        host.fakeStoryManager.recentRejections = [StoryRejectedQuest(
            event: "ADIA", quest: FormID(0x0200), reason: .conditionsFailed
        )]
        let state = try object(world.query(.story))
        guard case let .array(rejected) = state["rejected"], let rejection = rejected.first else {
            Issue.record("no rejected quest")
            return
        }
        #expect(object(rejection)["reason"] == .string("conditionsFailed"))
        #expect(state["fired"] == .object(["QSTR": .init(2)]))
        guard case let .array(recent) = state["recent"], let event = recent.first else {
            Issue.record("no recent event")
            return
        }
        #expect(object(event)["event"] == .string("QSTR"))
        #expect(object(event)["r1"] == .null)
    }

    @Test func theSocialStateListsEachConversationWatcherAndSentEvent() throws {
        let speaker = ReferenceKey.plugin(name: "test.esm", objectID: 0x100)
        let partner = ReferenceKey.plugin(name: "test.esm", objectID: 0x101)
        var saved = SocialState()
        saved.conversations = [SocialConversation(
            speaker: speaker, partner: partner, startedAt: 3, phase: .approaching
        )]
        saved.spectators[partner] = SocialSpectator(
            threats: [SocialThreat(attacker: speaker, target: nil, lastSeen: 1)], startedAt: 1
        )
        saved.bodyChecks[partner] = 4
        saved.socialTimers[speaker] = 9
        saved.recentPartners[speaker] = [partner]
        var look = SocialLook(nextCheck: 1, feet: .zero, checkedAt: 0)
        look.target = partner
        saved.looks[speaker] = look
        let social = FakeSocialEventPort()
        social.state = saved
        social.sentCounts = ["ADIA": 1]
        host.fakeStoryManager.social = social
        let state = try object(world.query(.social))
        #expect(state["sent"] == .object(["ADIA": .number(1)]))
        #expect(state["socialTimers"] == .object([speaker.description: .number(9)]))
        guard case let .array(talks) = state["conversations"], let talk = talks.first else {
            Issue.record("no conversation")
            return
        }
        #expect(object(talk)["phase"] == .string("approaching"))
        #expect(object(talk)["partner"] == .string(partner.description))
        guard case let .array(watchers) = state["watchers"], let watcher = watchers.first else {
            Issue.record("no watcher")
            return
        }
        #expect(object(watcher)["threats"] == .array([.string(speaker.description)]))
        #expect(object(watcher)["backsOff"] == .bool(false))
        #expect(state["lookTargets"] ==
            .object([speaker.description: .string(partner.description)]))
    }

    @Test func theMenuStateShowsEachScreen() throws {
        let state = try object(world.query(.menu))
        for screen in ["hud", "loading", "movie", "bink", "titles", "map"] {
            #expect(state[screen] != nil, "\(screen)")
        }
    }

    /// New asks first, so a script sees the question instead of a lost accept.
    @Test func anOpenTitleMenuShowsTheQuestionItAsks() throws {
        host.fakeTitleMenu.isOpen = true
        host.fakeTitleMenu.snapshotValue = TitleMenuSnapshot(
            rows: [], selectedIndex: 1, isLoadPageOpen: false,
            lastResult: "Asked: Start a new game?",
            movie: TitleMenuMovieSnapshot(isLoaded: true, state: "MainConfirm")
        )
        let state = try object(world.query(.menu))
        #expect(state["titleState"] == .string("MainConfirm"))
        #expect(state["titleResult"] == .string("Asked: Start a new game?"))
        #expect(state["credits"] == .bool(false))
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

    @Test func theAlarmStateListsWitnessesFightsAndTheMark() throws {
        let witness = ReferenceKey.generated(7)
        host.crimeAlarmReadout = CrimeAlarmReadout(
            witnesses: [.init(key: witness, role: "takeBack", criminal: .player, crimes: 1)],
            fighters: [.init(witness: witness, criminals: [.player])],
            angry: [witness], theftMarkDay: 3, openCrimes: 1, last: "Actor: takeBack"
        )
        let state = try object(world.query(.alarm))
        #expect(state["theftMarkDay"] == AgentJSON(3))
        #expect(state["openCrimes"] == AgentJSON(1))
        #expect(state["last"] == .string("Actor: takeBack"))
        guard case let .array(witnesses)? = state["witnesses"] else {
            Issue.record("no witness list")
            return
        }
        #expect(witnesses.first?.objectValue?["role"] == .string("takeBack"))
        #expect(witnesses.first?.objectValue?["criminal"] == .string("player"))
        #expect(state["fighters"]?.arrayValue?.count == 1)
        #expect(state["angry"]?.arrayValue?.count == 1)
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

extension AgentReadoutTests {
    /// A dead actor lists each ragdoll body with its bone, so a body far from the drawn
    /// actor shows up; a living one shows null.
    @Test func aDeadActorListsItsRagdollBodies() throws {
        let session = FakeGameSessionPort()
        session.freeFlyCameraValue = FreeFlyCamera(position: [0, 0, 0], yaw: 0, pitch: 0)
        host.gameSession = session
        host.fakeFactions.hostilityResult = .neutral
        host.fakeEffects.skinDecalsValue = SkinDecalRuntime()
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
        let dead = ReferenceKey.generated(9)
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: dead, feet: [10, 0, 0], name: "chicken"),
            CombatActorObservation(key: .generated(10), feet: [20, 0, 0], name: "dog")
        ]
        let runtime = FakeRagdollRuntimePort()
        var ragdolls = RagdollWorld()
        ragdolls.add(
            RagdollFixture.pair(origin: SIMD3(10, 0, 0)), for: dead, in: .interior(FormID(0x10))
        )
        runtime.worldValue = ragdolls
        host.fakeRagdoll.runtime = runtime
        let state = try object(world.query(.actors(radius: 1024)))
        guard case let .array(rows)? = state["actors"], rows.count == 2 else {
            Issue.record("no actor list")
            return
        }
        guard case let .array(bodies)? = object(rows[0])["ragdoll"] else {
            Issue.record("no ragdoll bodies")
            return
        }
        #expect(bodies.count == 2)
        #expect(object(bodies[0])["bone"] != nil)
        #expect(object(rows[1])["ragdoll"] == .null)
    }

    /// A town holds over 100 actors, and one reply line holds 64 KiB.
    @Test func aCrowdGetsShortRowsPastTheNearest() throws {
        let session = FakeGameSessionPort()
        session.freeFlyCameraValue = FreeFlyCamera(position: [0, 0, 0], yaw: 0, pitch: 0)
        host.gameSession = session
        host.fakeFactions.hostilityResult = .neutral
        host.fakeEffects.skinDecalsValue = SkinDecalRuntime()
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
        host.fakeActorWorld.combatActorsResult = (1 ... 100).map { index in
            CombatActorObservation(
                key: .generated(UInt64(index)), feet: [Float(index), 0, 0], name: "guard"
            )
        }
        let reply = try world.query(.actors(radius: 1024, detailed: 3))
        guard case let .array(rows)? = object(reply)["actors"], rows.count == 100 else {
            Issue.record("no actor list")
            return
        }
        #expect(object(rows[2])["bands"] != nil)
        #expect(object(rows[3])["bands"] == nil)
        #expect(object(rows[99])["distance"] == .init(Float(100)))
        #expect(AgentLineCodec.encode(reply).count < AgentProtocol.maximumLineBytes)
    }
}
