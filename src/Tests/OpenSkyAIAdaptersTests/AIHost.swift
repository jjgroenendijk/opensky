// One host for every AI adapter part, each port a generated fake.

import OpenSkyActorPresentation
import OpenSkyAIAdapters
import OpenSkyGameData
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkySessionTesting

@MainActor
final class AIHost: AIBumpsHost, AIDetectionSenseHost, AINavigationHost, AIPackageActsHost,
    AIPackageMovesHost, AIPackageStateHost, AIPerceptionSenseHost, AISeatingHost, AIWorldHost,
    FollowerCommandTasksHost, FollowerCommandWorldHost
{
    let fakeActorGraphWorld = FakeActorGraphWorldPort()
    let fakeActorValues = FakeActorValuePort()
    let fakeActorWorld = FakeActorWorldPort()
    let fakeAiWorld = FakeAIWorldPort()
    let fakeCombat = FakeCombatPort()
    let fakeCrime = FakeCrimePort()
    let fakeCrimeWorld = FakeCrimeWorldPort()
    let fakeDialogue = FakeDialoguePort()
    let fakeDialogueMenu = FakeDialogueMenuPort()
    let fakeDragonFlightWorld = FakeDragonFlightWorldPort()
    let fakeEffectsWorld = FakeEffectsWorldPort()
    let fakeFactions = FakeFactionPort()
    let fakeFollowerCommands = FakeFollowerCommandPort()
    let fakeFurniture = FakeFurniturePort()
    let fakeHeadTracking = FakeHeadTrackingPort()
    let fakeIdleWorld = FakeIdleWorldPort()
    let fakeInventory = FakeInventoryPort()
    let fakeInventoryWorld = FakeInventoryWorldPort()
    let fakeMagic = FakeMagicPort()
    let fakeMagicWorld = FakeMagicWorldPort()
    let fakeNpcAnimation = FakeNPCAnimationPort()
    let fakePackages = FakePackagePort()
    let fakePerception = FakePerceptionPort()
    let fakePerks = FakePerkPort()
    let fakeProgression = FakeProgressionPort()
    let fakeRuntimeState = FakeRuntimeStatePort()
    let fakeRuntimeStateWorld = FakeRuntimeStateWorldPort()
    let fakeScripts = FakeScriptPort()
    let fakeStoryWorld = FakeStoryWorldPort()
    let fakeStreamer = FakeCellStreamerPort()
    let fakeVehicleWorld = FakeVehicleWorldPort()
    let fakeWorldState = FakeWorldStateStorePort()
    var animationClips: ActorClipLoader?
    var gameSession: (any GameSessionPort)?
    var renderer: (any RendererPort)?
    var aiRecords: (any AIRecordsPort)?

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

    var combat: any CombatPort {
        fakeCombat
    }

    var crime: any CrimePort {
        fakeCrime
    }

    var crimeWorld: any CrimeWorldPort {
        fakeCrimeWorld
    }

    var dialogue: any DialoguePort {
        fakeDialogue
    }

    var dialogueMenu: any DialogueMenuPort {
        fakeDialogueMenu
    }

    var dragonFlightWorld: any DragonFlightWorldPort {
        fakeDragonFlightWorld
    }

    var effectsWorld: any EffectsWorldPort {
        fakeEffectsWorld
    }

    var factions: any FactionPort {
        fakeFactions
    }

    var followerCommands: any FollowerCommandPort {
        fakeFollowerCommands
    }

    var furniture: any FurniturePort {
        fakeFurniture
    }

    var headTracking: any HeadTrackingPort {
        fakeHeadTracking
    }

    var idleWorld: any IdleWorldPort {
        fakeIdleWorld
    }

    var inventory: any InventoryPort {
        fakeInventory
    }

    var inventoryWorld: any InventoryWorldPort {
        fakeInventoryWorld
    }

    var magic: any MagicPort {
        fakeMagic
    }

    var magicWorld: any MagicWorldPort {
        fakeMagicWorld
    }

    var npcAnimation: any NPCAnimationPort {
        fakeNpcAnimation
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

    var progression: any ProgressionPort {
        fakeProgression
    }

    var runtimeState: any RuntimeStatePort {
        fakeRuntimeState
    }

    var runtimeStateWorld: any RuntimeStateWorldPort {
        fakeRuntimeStateWorld
    }

    var scripts: any ScriptPort {
        fakeScripts
    }

    var storyWorld: any StoryWorldPort {
        fakeStoryWorld
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
}
