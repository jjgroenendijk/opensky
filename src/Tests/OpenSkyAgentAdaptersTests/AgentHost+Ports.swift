// The ports of the Agent test host: each returns its generated fake.

import CoreGraphics
import OpenSkyAgentAdapters
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState

extension AgentHost {
    var actorGraphs: any ActorGraphPort {
        fakeActorGraphs
    }

    var actorValues: any ActorValuePort {
        fakeActorValues
    }

    var actorWorld: any ActorWorldPort {
        fakeActorWorld
    }

    var agentWorld: any AgentWorldPort {
        fakeAgentWorld
    }

    var aiWorld: any AIWorldPort {
        fakeAiWorld
    }

    var audio: any AudioPort {
        fakeAudio
    }

    var beastForms: any BeastFormWorldPort {
        fakeBeastForms
    }

    var benchmarkTour: any BenchmarkTourPort {
        fakeBenchmarkTour
    }

    var benchmarkWorld: any BenchmarkWorldPort {
        fakeBenchmarkWorld
    }

    var cameraInput: any CameraInputStatePort {
        fakeCameraInput
    }

    var combat: any CombatPort {
        fakeCombat
    }

    var combatWorld: any CombatWorldPort {
        fakeCombatWorld
    }

    var containerMenu: any ContainerMenuPort {
        fakeContainerMenu
    }

    var controllerRumble: any ControllerRumblePort {
        fakeControllerRumble
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

    var effectGraphs: any EffectGraphPort {
        fakeEffectGraphs
    }

    var effectModelPoser: any EffectModelPoserPort {
        fakeEffectModelPoser
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

    var followerCommandWorld: any FollowerCommandWorldPort {
        fakeFollowerCommandWorld
    }

    var followerCommands: any FollowerCommandPort {
        fakeFollowerCommands
    }

    var furniture: any FurniturePort {
        fakeFurniture
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

    var inventoryMenu: any InventoryMenuPort {
        fakeInventoryMenu
    }

    var inventoryWorld: any InventoryWorldPort {
        fakeInventoryWorld
    }

    var journalMenu: any JournalMenuPort {
        fakeJournalMenu
    }

    var loadingScreens: any LoadingScreenPort {
        fakeLoadingScreens
    }

    var loadingWorld: any LoadingScreenWorldPort {
        fakeLoadingWorld
    }

    var magic: any MagicPort {
        fakeMagic
    }

    var mapMenu: any MapMenuPort {
        fakeMapMenu
    }

    var mapWorld: any MapWorldPort {
        fakeMapWorld
    }

    var menuMode: any MenuModePort {
        fakeMenuMode
    }

    var menuRouter: any MenuRouterPort {
        fakeMenuRouter
    }

    var menuScreensWorld: any MenuScreensWorldPort {
        fakeMenuScreensWorld
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

    var mounts: any MountPort {
        fakeMounts
    }

    var movies: any MoviePlayerPort {
        fakeMovies
    }

    var nodeControllers: any NodeControllerPort {
        fakeNodeControllers
    }

    var objectAnimationWorld: any ObjectAnimationWorldPort {
        fakeObjectAnimationWorld
    }

    var packages: any PackagePort {
        fakePackages
    }

    var perception: any PerceptionPort {
        fakePerception
    }

    var perks: any PerkPort {
        fakePerks
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

    var raceMenu: any RaceMenuPort {
        fakeRaceMenu
    }

    var ragdoll: any RagdollPort {
        fakeRagdoll
    }

    var renderControls: any WorldRenderControlsPort {
        fakeRenderControls
    }

    var runtimeState: any RuntimeStatePort {
        fakeRuntimeState
    }

    var scenes: any ScenePort {
        fakeScenes
    }

    var scripts: any ScriptPort {
        fakeScripts
    }

    var simulationClock: any SteppedWallClockPort {
        fakeSimulationClock
    }

    var skillsMenu: any SkillsMenuPort {
        fakeSkillsMenu
    }

    var streamer: any CellStreamerPort {
        fakeStreamer
    }

    var systemMenu: any SystemMenuPort {
        fakeSystemMenu
    }

    var titleMenu: any TitleMenuPort {
        fakeTitleMenu
    }

    var titleSequence: any TitleSequencePort {
        fakeTitleSequence
    }

    var vehicleWorld: any VehicleWorldPort {
        fakeVehicleWorld
    }

    var worldState: any WorldStateStorePort {
        fakeWorldState
    }
}
