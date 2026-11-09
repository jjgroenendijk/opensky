// One host for every Actor adapter part, each port a generated fake.

import OpenSkyActorAdapters
import OpenSkyActorPresentation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import simd

@MainActor
final class ActorHost: ActorGraphGraphEventsHost, ActorGraphWorldHost, ActorWorldHost,
    AnimationEventWorldHost, BeastFormWorldHost, DragonFlightCandidatesHost, DragonFlightWorldHost,
    EffectGraphWorldHost, IdlePlacementHost, IdleWorldHost, MountDragonRidingHost, MountWorldHost,
    ObjectAnimationWorldHost, PlayerFaceHost, PlayerFirstPersonHost, PlayerWorldHost,
    VehicleWorldHost
{
    let fakeActorGraphWorld = FakeActorGraphWorldPort()
    let fakeActorGraphs = FakeActorGraphPort()
    let fakeActorValues = FakeActorValuePort()
    let fakeActorWorld = FakeActorWorldPort()
    let fakeAiWorld = FakeAIWorldPort()
    let fakeAudio = FakeAudioPort()
    let fakeCinematicCamera = FakeCinematicCameraPort()
    let fakeCombat = FakeCombatPort()
    let fakeCombatWorld = FakeCombatWorldPort()
    let fakeContainerMenu = FakeContainerMenuPort()
    let fakeCrime = FakeCrimePort()
    let fakeDialogueMenu = FakeDialogueMenuPort()
    let fakeDragonFlight: FakeDragonFlightPort = {
        let fake = FakeDragonFlightPort()
        fake.phaseResult = .grounded
        return fake
    }()

    let fakeEffectGraphs = FakeEffectGraphPort()
    let fakeEffects = FakeEffectsPort()
    let fakeHeadTracking = FakeHeadTrackingPort()
    let fakeHud = FakeHUDPort()
    let fakeIdleWorld = FakeIdleWorldPort()
    let fakeIdles = FakeIdlePort()
    let fakeInventory = FakeInventoryPort()
    let fakeJournal = FakeJournalPort()
    let fakeMagic = FakeMagicPort()
    let fakeMagicWorld = FakeMagicWorldPort()
    let fakeMapWorld = FakeMapWorldPort()
    let fakeMenuWorld = FakeMenuWorldPort()
    let fakeMessages = FakeMessageCoordinatorPort()
    let fakeMounts = FakeMountPort()
    let fakeNodeControllers = FakeNodeControllerPort()
    let fakeObjectAnimationWorld = FakeObjectAnimationWorldPort()
    let fakeObjectBehaviors = FakeObjectBehaviorPort()
    let fakePackages = FakePackagePort()
    let fakePerks = FakePerkPort()
    let fakePlayer = FakePlayerPort()
    let fakeRuntimeStateWorld = FakeRuntimeStateWorldPort()
    let fakeScripts = FakeScriptPort()
    let fakeSequenceDoors = FakeSequenceDoorPort()
    let fakeStreamer = FakeCellStreamerPort()
    let fakeVehicleWorld = FakeVehicleWorldPort()
    let fakeVehicles = FakeVehiclePort()
    let fakeWorldState = FakeWorldStateStorePort()
    var animationClips: ActorClipLoader?
    var audioFileSystem: (any GameFileSource)?
    var cellRunner: (any SerialCellBuildRunnerPort)?
    var gameSession: (any GameSessionPort)?
    var renderer: (any RendererPort)?
    var actorRecords: (any ActorRecordsPort)?
    var playbacks: [ReferenceKey: any ActorAnimationPlaybackPort] = [:]
    var poses: [ReferenceKey: [String: float4x4]] = [:]
    private(set) var playerBodyCount = 0
    private(set) var firstPersonRigCount = 0

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

    var dialogueMenu: any DialogueMenuPort {
        fakeDialogueMenu
    }

    var dragonFlight: any DragonFlightPort {
        fakeDragonFlight
    }

    var effectGraphs: any EffectGraphPort {
        fakeEffectGraphs
    }

    var effects: any EffectsPort {
        fakeEffects
    }

    var headTracking: any HeadTrackingPort {
        fakeHeadTracking
    }

    var hud: any HUDPort {
        fakeHud
    }

    var idleWorld: any IdleWorldPort {
        fakeIdleWorld
    }

    var idles: any IdlePort {
        fakeIdles
    }

    var inventory: any InventoryPort {
        fakeInventory
    }

    var journal: any JournalPort {
        fakeJournal
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

    var mounts: any MountPort {
        fakeMounts
    }

    var nodeControllers: any NodeControllerPort {
        fakeNodeControllers
    }

    var objectAnimationWorld: any ObjectAnimationWorldPort {
        fakeObjectAnimationWorld
    }

    var objectBehaviors: any ObjectBehaviorPort {
        fakeObjectBehaviors
    }

    var packages: any PackagePort {
        fakePackages
    }

    var perks: any PerkPort {
        fakePerks
    }

    var player: any PlayerPort {
        fakePlayer
    }

    var runtimeStateWorld: any RuntimeStateWorldPort {
        fakeRuntimeStateWorld
    }

    var scripts: any ScriptPort {
        fakeScripts
    }

    var sequenceDoors: any SequenceDoorPort {
        fakeSequenceDoors
    }

    var streamer: any CellStreamerPort {
        fakeStreamer
    }

    var vehicleWorld: any VehicleWorldPort {
        fakeVehicleWorld
    }

    var vehicles: any VehiclePort {
        fakeVehicles
    }

    var worldState: any WorldStateStorePort {
        fakeWorldState
    }

    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)? {
        playbacks[key]
    }

    func animatedPose(for key: ReferenceKey) -> [String: float4x4]? {
        poses[key]
    }

    func setPlayerBody(_: PlayerBody) throws {
        playerBodyCount += 1
    }

    func setPlayerFirstPersonRig(_: PlayerFirstPersonRig) throws {
        firstPersonRigCount += 1
    }
}
