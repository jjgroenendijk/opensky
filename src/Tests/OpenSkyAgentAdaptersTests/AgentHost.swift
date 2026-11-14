// One host for every Agent adapter part, each port a generated fake.

import CoreGraphics
import OpenSkyAgentAdapters
import OpenSkyEngineTesting
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState

@MainActor
final class AgentHost: RendererSlotHost, AgentActorReadoutHost, AgentActorsHost, AgentBehaviourHost,
    AgentCaptureHost, AgentEventsHost, AgentFrameReadoutHost, AgentInputHost, AgentItemsHost,
    AgentMenuReadoutHost, AgentMotionHost, AgentObjectsHost, AgentPlayerReadoutHost,
    AgentRenderHost, AgentScreensHost, AgentViewHost, AgentWorldHost, BenchmarkTourSettingsHost,
    BenchmarkWorldHost
{
    let fakeActorGraphs = FakeActorGraphPort()
    let fakeActorValues = FakeActorValuePort()
    let fakeActorWorld = FakeActorWorldPort()
    let fakeAgentWorld = FakeAgentWorldPort()
    let fakeAiWorld = FakeAIWorldPort()
    let fakeAudio = FakeAudioPort()
    let fakeBeastForms = FakeBeastFormWorldPort()
    let fakeBenchmarkTour = FakeBenchmarkTourPort()
    let fakeBenchmarkWorld = FakeBenchmarkWorldPort()
    let fakeCameraInput = FakeCameraInputStatePort()
    let fakeCombat = FakeCombatPort()
    let fakeCombatWorld = FakeCombatWorldPort()
    let fakeContainerMenu = FakeContainerMenuPort()
    let fakeControllerRumble = FakeControllerRumblePort()
    let fakeDialogueMenu = FakeDialogueMenuPort()
    let fakeDialogueWorld = FakeDialogueWorldPort()
    let fakeDragonFlight: FakeDragonFlightPort = {
        let fake = FakeDragonFlightPort()
        fake.phaseResult = .grounded
        return fake
    }()

    let fakeDragonFlightWorld = FakeDragonFlightWorldPort()
    let fakeEffectGraphs = FakeEffectGraphPort()
    let fakeEffectModelPoser = FakeEffectModelPoserPort()
    let fakeEffects = FakeEffectsPort()
    let fakeEffectsWorld = FakeEffectsWorldPort()
    let fakeFactions = FakeFactionPort()
    let fakeFollowerCommandWorld = FakeFollowerCommandWorldPort()
    let fakeFollowerCommands = FakeFollowerCommandPort()
    let fakeFurniture = FakeFurniturePort()
    let fakeHud = FakeHUDPort()
    let fakeIdleWorld = FakeIdleWorldPort()
    let fakeInventory = FakeInventoryPort()
    let fakeInventoryMenu = FakeInventoryMenuPort()
    let fakeInventoryWorld = FakeInventoryWorldPort()
    let fakeJournalMenu = FakeJournalMenuPort()
    let fakeLoadingScreens = FakeLoadingScreenPort()
    let fakeLoadingWorld = FakeLoadingScreenWorldPort()
    let fakeMagic = FakeMagicPort()
    let fakeMapMenu = FakeMapMenuPort()
    let fakeMapWorld = FakeMapWorldPort()
    let fakeMenuMode: FakeMenuModePort = {
        let fake = FakeMenuModePort()
        fake.stack = MenuStack()
        return fake
    }()

    let fakeMenuRouter = FakeMenuRouterPort()
    let fakeMenuScreensWorld = FakeMenuScreensWorldPort()
    let fakeMenuWorld = FakeMenuWorldPort()
    let fakeMessages = FakeMessageCoordinatorPort()
    let fakeMountWorld = FakeMountWorldPort()
    let fakeMounts = FakeMountPort()
    let fakeMovies = FakeMoviePlayerPort()
    let fakeNodeControllers = FakeNodeControllerPort()
    let fakeObjectAnimationWorld = FakeObjectAnimationWorldPort()
    let fakePackages = FakePackagePort()
    let fakePerception = FakePerceptionPort()
    let fakePerks = FakePerkPort()
    let fakePlayer = FakePlayerPort()
    let fakePlayerSettings = FakePlayerSettingsPort()
    let fakeProgression = FakeProgressionPort()
    let fakeRaceMenu = FakeRaceMenuPort()
    let fakeRagdoll = FakeRagdollPort()
    let fakeRenderControls = FakeWorldRenderControlsPort()
    let fakeRuntimeState: FakeRuntimeStatePort = {
        let fake = FakeRuntimeStatePort()
        fake.runtimeStateClock = RuntimeStateClockSnapshot(clock: GameClock(hour: 9), timescale: 20)
        return fake
    }()

    let fakeScenes = FakeScenePort()
    let fakeScripts = FakeScriptPort()
    let fakeSimulationClock = FakeSteppedWallClockPort()
    let fakeSkillsMenu = FakeSkillsMenuPort()
    let fakeStreamer = {
        let fake = FakeCellStreamerPort()
        fake.coverageReadoutValue = CellCoverageReadout(
            center: CellCoordinate(x: 0, y: 0), wantedCells: [], drawnCells: [],
            waitingCells: [], ringCenter: nil, ringBuilding: false, ringSwaps: 0
        )
        return fake
    }()

    let fakeSystemMenu = FakeSystemMenuPort()
    let fakeTitleMenu = FakeTitleMenuPort()
    let fakeTitleSequence = FakeTitleSequencePort()
    let fakeVehicleWorld = FakeVehicleWorldPort()
    let fakeWorldState = FakeWorldStateStorePort()
    var benchmarkLoadPhases: (any LoadPhaseRecorderPort)?
    var dataRoot: GameDataRoot?
    var drawableSize = CGSize.zero
    var gameSession: (any GameSessionPort)?
    var playerBeastForm = PlayerBeastForm.none
    var playerControlLocks = PlayerControlLocks.none
    var playerSettingsStore = PlayerSettingsStore(persistence: nil)
    var sessionStartTiming = SessionStartTiming()
    var terrainLODConfigurationStore = TerrainLODConfigurationStore.fallback()
    var viewBounds = CGRect.zero
    var playbacks: [ReferenceKey: any ActorAnimationPlaybackPort] = [:]
    private(set) var commands: [GameInputAction] = []
    private(set) var refusals: [PlayerControlRefusal] = []
    var worldLoadReport: WorldLoadReport?

    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)? {
        playbacks[key]
    }

    func runCommand(_ action: GameInputAction) {
        commands.append(action)
    }

    func showControlRefusal(_ refusal: PlayerControlRefusal) {
        refusals.append(refusal)
    }
}
