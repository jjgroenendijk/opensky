// One host for every Session adapter part, each port a generated fake.

import Foundation
import OpenSkyAudio
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyRendering
import OpenSkySessionAdapters
import OpenSkySessionInterface
import OpenSkySessionTesting

@MainActor
final class SessionHost: AudioListenerHost, AudioMixHost, AudioWorldHost,
    RuntimeStateConditionReadsHost,
    RuntimeStateInventoryFactsHost, RuntimeStateLiveSeamsHost, RuntimeStateReferenceMotionHost,
    RuntimeStateSaveContentsHost, RuntimeStateSessionClockHost, RuntimeStateSessionLoadHost,
    RuntimeStateWorldHost, SaveGameWorldHost, SkyrimSaveExportHost, SkyrimSaveImportHost
{
    let fakeActorGraphWorld = FakeActorGraphWorldPort()
    let fakeActorValues = FakeActorValuePort()
    let fakeActorWorld = FakeActorWorldPort()
    let fakeAiWorld = FakeAIWorldPort()
    let fakeAudio = FakeAudioPort()
    let fakeCombat = FakeCombatPort()
    let fakeCombatWorld = FakeCombatWorldPort()
    let fakeControllerRumble = FakeControllerRumblePort()
    let fakeCrime = FakeCrimePort()
    let fakeDialogue = FakeDialoguePort()
    let fakeDialogueMenu = FakeDialogueMenuPort()
    let fakeDialogueWorld = FakeDialogueWorldPort()
    let fakeDragonFlight = FakeDragonFlightPort()
    let fakeDragonFlightWorld = FakeDragonFlightWorldPort()
    let fakeEffects = FakeEffectsPort()
    let fakeEffectsWorld = FakeEffectsWorldPort()
    let fakeFactions = FakeFactionPort()
    let fakeHud = FakeHUDPort()
    let fakeIdleWorld = FakeIdleWorldPort()
    let fakeInventory = FakeInventoryPort()
    let fakeLoadingScreens = FakeLoadingScreenPort()
    let fakeMagic = FakeMagicPort()
    let fakeMapWorld = FakeMapWorldPort()
    let fakeMenuMode: FakeMenuModePort = {
        let fake = FakeMenuModePort()
        fake.stack = MenuStack()
        return fake
    }()

    let fakeMenuWorld = FakeMenuWorldPort()
    let fakeMessages = FakeMessageCoordinatorPort()
    let fakeMountWorld = FakeMountWorldPort()
    let fakePackages = FakePackagePort()
    let fakePerception = FakePerceptionPort()
    let fakePlayer = FakePlayerPort()
    let fakePlayerSettings = FakePlayerSettingsPort()
    let fakeProgression = FakeProgressionPort()
    let fakeQuestNotices = FakeQuestNoticePort()
    let fakeRagdoll = FakeRagdollPort()
    let fakeRuntimeState = FakeRuntimeStatePort()
    let fakeRuntimeStateWorld = FakeRuntimeStateWorldPort()
    let fakeScenes = FakeScenePort()
    let fakeScripts = FakeScriptPort()
    let fakeStreamer = FakeCellStreamerPort()
    let fakeVehicleWorld = FakeVehicleWorldPort()
    let fakeWorldState = FakeWorldStateStorePort()
    var audioFileSystem: (any GameFileSource)?
    var gameSession: (any GameSessionPort)?
    var renderer: (any RendererPort)?
    var soundMixTimings = SoundMixTimings()
    var exportDate = Date(timeIntervalSinceReferenceDate: 0)
    var sessionRecords: (any SessionRecordsPort)?
    private(set) var startedAudioCount = 0

    var actorGraphWorld: any ActorGraphWorldPort {
        fakeActorGraphWorld
    }

    var actorValues: any ActorValuePort {
        fakeActorValues
    }

    var actorWorld: any ActorWorldPort {
        fakeActorWorld
    }

    var aiWorld: any AIWorldPort {
        fakeAiWorld
    }

    var audio: any AudioPort {
        fakeAudio
    }

    var combat: any CombatPort {
        fakeCombat
    }

    var combatWorld: any CombatWorldPort {
        fakeCombatWorld
    }

    var controllerRumble: any ControllerRumblePort {
        fakeControllerRumble
    }

    var crime: any CrimePort {
        fakeCrime
    }

    var dialogue: any DialoguePort {
        fakeDialogue
    }

    var dialogueMenu: any DialogueMenuPort {
        fakeDialogueMenu
    }

    var dialogueWorld: any DialogueWorldPort {
        fakeDialogueWorld
    }

    var dragonFlight: any DragonFlightPort {
        fakeDragonFlight
    }

    var dragonFlightWorld: any DragonFlightWorldPort {
        fakeDragonFlightWorld
    }

    var effects: any EffectsPort {
        fakeEffects
    }

    var effectsWorld: any EffectsWorldPort {
        fakeEffectsWorld
    }

    var factions: any FactionPort {
        fakeFactions
    }

    var hud: any HUDPort {
        fakeHud
    }

    var idleWorld: any IdleWorldPort {
        fakeIdleWorld
    }

    var inventory: any InventoryPort {
        fakeInventory
    }

    var loadingScreens: any LoadingScreenPort {
        fakeLoadingScreens
    }

    var magic: any MagicPort {
        fakeMagic
    }

    var mapWorld: any MapWorldPort {
        fakeMapWorld
    }

    var menuMode: any MenuModePort {
        fakeMenuMode
    }

    var menuWorld: any MenuWorldPort {
        fakeMenuWorld
    }

    var messages: any MessageCoordinatorPort {
        fakeMessages
    }

    var mountWorld: any MountWorldPort {
        fakeMountWorld
    }

    var packages: any PackagePort {
        fakePackages
    }

    var perception: any PerceptionPort {
        fakePerception
    }

    var player: any PlayerPort {
        fakePlayer
    }

    var playerSettings: any PlayerSettingsPort {
        fakePlayerSettings
    }

    var progression: any ProgressionPort {
        fakeProgression
    }

    var questNotices: any QuestNoticePort {
        fakeQuestNotices
    }

    var ragdoll: any RagdollPort {
        fakeRagdoll
    }

    var runtimeState: any RuntimeStatePort {
        fakeRuntimeState
    }

    var runtimeStateWorld: any RuntimeStateWorldPort {
        fakeRuntimeStateWorld
    }

    var scenes: any ScenePort {
        fakeScenes
    }

    var scripts: any ScriptPort {
        fakeScripts
    }

    var streamer: any CellStreamerPort {
        fakeStreamer
    }

    var vehicleWorld: any VehicleWorldPort {
        fakeVehicleWorld
    }

    var worldState: any WorldStateStorePort {
        fakeWorldState
    }

    func takeStartedAudio(_: StartedAudio) {
        startedAudioCount += 1
    }
}
