// One host for every Story adapter part, each port a generated fake.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyStoryAdapters
import simd

@MainActor
final class StoryHost: CrimeActorsHost, CrimeFactionsHost, CrimeJailHost, CrimeWorldHost,
    DialogueCameraFocusHost, DialogueOutcomesHost, DialogueSpeakersHost, DialogueWorldHost,
    StoryAmbientTalkHost, StorySceneCastHost, StorySceneLinesHost, StorySocialSearchHost,
    StoryWorldHost
{
    let fakeActorWorld = FakeActorWorldPort()
    let fakeAiWorld = FakeAIWorldPort()
    let fakeAudio = FakeAudioPort()
    let fakeCombat = FakeCombatPort()
    let fakeContainerMenu = FakeContainerMenuPort()
    let fakeCrime = FakeCrimePort()
    let fakeDialogue = FakeDialoguePort()
    let fakeDialogueCamera = FakeDialogueCameraPort()
    let fakeDialogueMenu = FakeDialogueMenuPort()
    let fakeDialogueWorld = FakeDialogueWorldPort()
    let fakeFaceMorphs = FakeFaceMorphPort()
    let fakeFactions = FakeFactionPort()
    let fakeFollowerCommandWorld = FakeFollowerCommandWorldPort()
    let fakeHeadTracking = FakeHeadTrackingPort()
    let fakeHud = FakeHUDPort()
    let fakeIdles = FakeIdlePort()
    let fakeInventory = FakeInventoryPort()
    let fakeInventoryWorld = FakeInventoryWorldPort()
    let fakeMapWorld = FakeMapWorldPort()
    let fakeMountWorld = FakeMountWorldPort()
    let fakePackages = FakePackagePort()
    let fakePerception = FakePerceptionPort()
    let fakePerks = FakePerkPort()
    let fakePlayer = FakePlayerPort()
    let fakeProgression = FakeProgressionPort()
    let fakeRuntimeState = FakeRuntimeStatePort()
    let fakeScenes = FakeScenePort()
    let fakeScripts = FakeScriptPort()
    let fakeStoryManager = FakeStoryManagerPort()
    let fakeStoryWorld = FakeStoryWorldPort()
    let fakeStreamer = FakeCellStreamerPort()
    let fakeSubtitles = FakeSubtitlePort()
    let fakeWorldState = FakeWorldStateStorePort()
    var audioFileSystem: (any GameFileSource)?
    var gameSession: (any GameSessionPort)?
    var localizedStringsLoader: (() -> LocalizedStrings)?
    var renderer: (any RendererPort)?
    var worldRecords: (any WorldRecordsPort)?
    var poses: [ReferenceKey: [String: float4x4]] = [:]

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

    var containerMenu: any ContainerMenuPort {
        fakeContainerMenu
    }

    var crime: any CrimePort {
        fakeCrime
    }

    var dialogue: any DialoguePort {
        fakeDialogue
    }

    var dialogueCamera: any DialogueCameraPort {
        fakeDialogueCamera
    }

    var dialogueMenu: any DialogueMenuPort {
        fakeDialogueMenu
    }

    var dialogueWorld: any DialogueWorldPort {
        fakeDialogueWorld
    }

    var faceMorphs: any FaceMorphPort {
        fakeFaceMorphs
    }

    var factions: any FactionPort {
        fakeFactions
    }

    var followerCommandWorld: any FollowerCommandWorldPort {
        fakeFollowerCommandWorld
    }

    var headTracking: any HeadTrackingPort {
        fakeHeadTracking
    }

    var hud: any HUDPort {
        fakeHud
    }

    var idles: any IdlePort {
        fakeIdles
    }

    var inventory: any InventoryPort {
        fakeInventory
    }

    var inventoryWorld: any InventoryWorldPort {
        fakeInventoryWorld
    }

    var mapWorld: any MapWorldPort {
        fakeMapWorld
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

    var perks: any PerkPort {
        fakePerks
    }

    var player: any PlayerPort {
        fakePlayer
    }

    var progression: any ProgressionPort {
        fakeProgression
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

    var storyManager: any StoryManagerPort {
        fakeStoryManager
    }

    var storyWorld: any StoryWorldPort {
        fakeStoryWorld
    }

    var streamer: any CellStreamerPort {
        fakeStreamer
    }

    var subtitles: any SubtitlePort {
        fakeSubtitles
    }

    var worldState: any WorldStateStorePort {
        fakeWorldState
    }

    func animatedPose(for key: ReferenceKey) -> [String: float4x4]? {
        poses[key]
    }
}
