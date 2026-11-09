// One host for every Combat adapter part, each port a generated fake.

import OpenSkyActorPresentation
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkySessionTesting
import simd

@MainActor
final class CombatHost: CinematicCameraWorldHost, CombatActorFactsHost, CombatGearHost,
    CombatImpactEffectsHost, CombatMotionHost, CombatOutcomesHost, CombatReportsHost,
    CombatSpellCastsHost, CombatWorldHost, EffectsBlastsHost, EffectsBodyImpulsesHost,
    EffectsEffectPlacementHost, EffectsLocatorHost, EffectsTrapControlHost, EffectsWorldHost,
    RagdollDeathsHost, RagdollPlayerFallHost, RagdollPoseReadsHost, RagdollRecoveryHost,
    RagdollRemainsHost, RagdollWorldHost
{
    let fakeActorGraphWorld = FakeActorGraphWorldPort()
    let fakeActorGraphs = FakeActorGraphPort()
    let fakeActorValues = FakeActorValuePort()
    let fakeActorWorld = FakeActorWorldPort()
    let fakeAiWorld = FakeAIWorldPort()
    let fakeAudio = FakeAudioPort()
    let fakeCinematicCamera = FakeCinematicCameraPort()
    let fakeCinematicWorld = FakeCinematicCameraWorldPort()
    let fakeCombat = FakeCombatPort()
    let fakeCombatWorld = FakeCombatWorldPort()
    let fakeContainerMenu = FakeContainerMenuPort()
    let fakeControllerRumble = FakeControllerRumblePort()
    let fakeCrime = FakeCrimePort()
    let fakeDialogue = FakeDialoguePort()
    let fakeEffects = FakeEffectsPort()
    let fakeEffectsWorld = FakeEffectsWorldPort()
    let fakeFactions = FakeFactionPort()
    let fakeHazardWorld = FakeHazardWorldPort()
    let fakeHazards = FakeHazardPort()
    let fakeHud = FakeHUDPort()
    let fakeIdleWorld = FakeIdleWorldPort()
    let fakeInventory = FakeInventoryPort()
    let fakeMagic = FakeMagicPort()
    let fakeMagicWorld = FakeMagicWorldPort()
    let fakeMapWorld = FakeMapWorldPort()
    let fakeMenuWorld = FakeMenuWorldPort()
    let fakeMessages = FakeMessageCoordinatorPort()
    let fakePackages = FakePackagePort()
    let fakePerception = FakePerceptionPort()
    let fakePerks = FakePerkPort()
    let fakePlayer = FakePlayerPort()
    let fakeProgression = FakeProgressionPort()
    let fakeRagdoll = FakeRagdollPort()
    let fakeRagdollWorld = FakeRagdollWorldPort()
    let fakeRuntimeState = FakeRuntimeStatePort()
    let fakeSaveGames = FakeSaveGameWorldPort()
    let fakeScripts = FakeScriptPort()
    let fakeStoryWorld = FakeStoryWorldPort()
    let fakeStreamer = FakeCellStreamerPort()
    let fakeTitleMenu = FakeTitleMenuPort()
    let fakeWorldState = FakeWorldStateStorePort()
    var combatRecords: (any CombatRecordsPort)?
    var renderer: (any RendererPort)?
    var gameSession: (any GameSessionPort)?
    var audioFileSystem: (any GameFileSource)?
    var animationClips: ActorClipLoader?
    var animatedPoses: [ReferenceKey: [String: float4x4]] = [:]
    var playbacks: [ReferenceKey: any ActorAnimationPlaybackPort] = [:]
    var quitToMainMenuCalls = 0

    var actorGraphWorld: any ActorGraphWorldPort {
        fakeActorGraphWorld
    }

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
        fakeAiWorld
    }

    var audio: any AudioPort {
        fakeAudio
    }

    var cinematicCamera: any CinematicCameraPort {
        fakeCinematicCamera
    }

    var cinematicWorld: any CinematicCameraWorldPort {
        fakeCinematicWorld
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

    var crime: any CrimePort {
        fakeCrime
    }

    var dialogue: any DialoguePort {
        fakeDialogue
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

    var hazardWorld: any HazardWorldPort {
        fakeHazardWorld
    }

    var hazards: any HazardPort {
        fakeHazards
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

    var ragdollWorld: any RagdollWorldPort {
        fakeRagdollWorld
    }

    var runtimeState: any RuntimeStatePort {
        fakeRuntimeState
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

    var titleMenu: any TitleMenuPort {
        fakeTitleMenu
    }

    var worldState: any WorldStateStorePort {
        fakeWorldState
    }

    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)? {
        playbacks[key]
    }

    func animatedPose(for key: ReferenceKey) -> [String: float4x4]? {
        animatedPoses[key]
    }

    func quitToMainMenu() {
        quitToMainMenuCalls += 1
    }
}
