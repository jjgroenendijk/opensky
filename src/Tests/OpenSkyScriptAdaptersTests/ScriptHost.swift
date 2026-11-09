// One host for every Script adapter, each port a generated fake.

import CoreGraphics
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyScriptAdapters
import OpenSkySessionInterface
import OpenSkySessionTesting

@MainActor
final class ScriptHost: ScriptWorldHost, ScriptActorBindingsHost, ScriptPerkBindingsHost,
    ScriptSessionBindingsHost, ScriptPlayerBindingsHost, ScriptReferenceBindingsHost,
    ScriptSoundBindingsHost, ScriptPhysicsBindingsHost, ScriptNodeBindingsHost,
    ScriptSkyBindingsHost,
    ScriptFeatureBindingsHost
{
    let fakeActorGraphs = FakeActorGraphPort()
    let fakeActorValues = FakeActorValuePort()
    let fakeActorWorld = FakeActorWorldPort()
    let fakeAIWorld = FakeAIWorldPort()
    let fakeAudio = FakeAudioPort()
    let fakeCombat = FakeCombatPort()
    let fakeCombatWorld = FakeCombatWorldPort()
    let fakeContainerMenu = FakeContainerMenuPort()
    let fakeCrime = FakeCrimePort()
    let fakeEffects = FakeEffectsPort()
    let fakeEffectsWorld = FakeEffectsWorldPort()
    let fakeFactionWorld = FakeFactionWorldPort()
    let fakeHUD = FakeHUDPort()
    let fakeInventory = FakeInventoryPort()
    let fakeInventoryWorld = FakeInventoryWorldPort()
    let fakeMagic = FakeMagicPort()
    let fakeMagicWorld = FakeMagicWorldPort()
    let fakeMapWorld = FakeMapWorldPort()
    let fakeMenuWorld = FakeMenuWorldPort()
    let fakeMessages = FakeMessageCoordinatorPort()
    let fakeMountWorld = FakeMountWorldPort()
    let fakeMovieWorld = FakeMovieWorldPort()
    let fakeObjectAnimationWorld = FakeObjectAnimationWorldPort()
    let fakePackages = FakePackagePort()
    let fakePerception = FakePerceptionPort()
    let fakePerks = FakePerkPort()
    let fakePlayer = FakePlayerPort()
    let fakeProgression = FakeProgressionPort()
    let fakeRagdoll = FakeRagdollPort()
    let fakeRuntimeState = FakeRuntimeStatePort()
    let fakeRuntimeStateWorld = FakeRuntimeStateWorldPort()
    let fakeSaveGames = FakeSaveGameWorldPort()
    let fakeScripts = FakeScriptPort()
    let fakeStoryWorld = FakeStoryWorldPort()
    let fakeStreamer = FakeCellStreamerPort()
    let fakeTitleSequence = FakeTitleSequencePort()
    let fakeVehicleWorld = FakeVehicleWorldPort()
    let fakeWorldState = FakeWorldStateStorePort()

    var actorGraphs: any ActorGraphPort {
        fakeActorGraphs
    }

    var actorValues: any ActorValuePort {
        fakeActorValues
    }

    var actorWorld: any ActorWorldPort {
        fakeActorWorld
    }

    var aiWorld: any AIWorldPort {
        fakeAIWorld
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

    var containerMenu: any ContainerMenuPort {
        fakeContainerMenu
    }

    var crime: any CrimePort {
        fakeCrime
    }

    var effects: any EffectsPort {
        fakeEffects
    }

    var effectsWorld: any EffectsWorldPort {
        fakeEffectsWorld
    }

    var factionWorld: any FactionWorldPort {
        fakeFactionWorld
    }

    var hud: any HUDPort {
        fakeHUD
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

    var mapWorld: any MapWorldPort {
        fakeMapWorld
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

    var movieWorld: any MovieWorldPort {
        fakeMovieWorld
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

    var progression: any ProgressionPort {
        fakeProgression
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

    var saveGames: any SaveGameWorldPort {
        fakeSaveGames
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

    var titleSequence: any TitleSequencePort {
        fakeTitleSequence
    }

    var vehicleWorld: any VehicleWorldPort {
        fakeVehicleWorld
    }

    var worldState: any WorldStateStorePort {
        fakeWorldState
    }

    var audioFileSystem: (any GameFileSource)?
    var drawableSize = CGSize(width: 1280, height: 720)
    var gameSession: (any GameSessionPort)?
    var worldRecords: (any WorldRecordsPort)?
    var renderer: (any RendererPort)?
    var quitApplicationCallCount = 0
    var quitToMainMenuCallCount = 0

    func quitApplication() {
        quitApplicationCallCount += 1
    }

    func quitToMainMenu() {
        quitToMainMenuCallCount += 1
    }

    func actorPlayback(for _: ReferenceKey) -> (any ActorAnimationPlaybackPort)? {
        nil
    }
}
