// The scope reaches its ports and factories through these protocols, so it does not
// name the types that read it back (design rule 4, docs/decisions/design-metrics.md).

import AppKit
import Foundation
import MetalKit
import OpenSkyActorAdapters
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAgentAdapters
import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryAdapters
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMagic
import OpenSkyMagicAdapters
import OpenSkyMagicInterface
import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyObjectAnimation
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionAdapters
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptAdapters
import OpenSkyScripting
import OpenSkySessionAdapters
import OpenSkySessionInterface
import OpenSkyStoryAdapters
import OpenSkyWorld
import OpenSkyWorldState

/// Every adapter host the session ports answer, so each adapter sees only its part.
protocol SessionPortSet:
    AIWorldHost, ActivationRefusalWorldHost, ActorGraphWorldHost, ActorWorldHost, AgentWorldHost,
    AnimationEventWorldHost, AudioWorldHost, BeastFormWorldHost, BenchmarkWorldHost,
    CinematicCameraWorldHost, CombatWorldHost, ContainerMenuHost, CrimeWorldHost,
    DialogueCameraHost, DialogueMenuHost, DialogueWorldHost, DragonFlightWorldHost,
    EffectGraphWorldHost, EffectsWorldHost, FollowerCommandWorldHost, IdleWorldHost,
    InventoryMenuHost, InventoryWorldHost, JournalMenuHost, LoadingScreenWorldHost, LockWorldHost,
    LockpickingMenuHost, MagicWorldHost, MapWorldHost, MenuHotkeyHost,
    MenuTickHost, MenuPlayRoutesHost, MenuFrontRoutesHost, MenuScreensHost, MenuScreensWorldHost,
    MenuSoundHost, MenuWorldHost, MessageWorldHost, MountWorldHost, MovieWorldHost,
    ObjectAnimationWorldHost, PerkActivationWorldHost, PlayerWorldHost, ProgressionWorldHost,
    RagdollWorldHost, RuntimeStateWorldHost, SaveGameWorldHost, ScriptWorldHost,
    SkyrimSaveExportHost, SkyrimSaveImportHost, StoryWorldHost, VehicleWorldHost, SystemMenuWorld,
    AgentRenderHost, AgentActorsHost, AgentMotionHost, AgentBehaviourHost, AgentObjectsHost,
    AgentMenuReadoutHost, AgentScreensHost, AgentEventsHost, AgentPlayerReadoutHost,
    AgentFrameReadoutHost, AgentActorReadoutHost, AgentItemsHost, AgentViewHost, AgentInputHost,
    AgentCaptureHost, ScriptActorBindingsHost, ScriptPerkBindingsHost, ScriptSessionBindingsHost,
    ScriptPlayerBindingsHost, ScriptReferenceBindingsHost, ScriptSoundBindingsHost,
    ScriptPhysicsBindingsHost, ScriptNodeBindingsHost, ScriptSkyBindingsHost,
    ScriptFeatureBindingsHost, AISeatingHost, AIDetectionSenseHost, AIPerceptionSenseHost,
    AINavigationHost, AIPackageMovesHost, AIPackageStateHost, AIPackageActsHost, AIBumpsHost,
    CombatSpellCastsHost, CombatImpactEffectsHost, CombatReportsHost, CombatActorFactsHost,
    CombatGearHost, CombatMotionHost, CombatOutcomesHost, MagicArchetypeEffectsHost,
    MagicSpellDeliveryHost, MagicHeldMagicHost, MagicSummonedActorsHost, MagicWorldFactsHost,
    EffectsBodyImpulsesHost, EffectsLocatorHost, EffectsTrapControlHost, EffectsBlastsHost,
    EffectsEffectPlacementHost,
    RagdollRecoveryHost, RagdollRemainsHost, RagdollPlayerFallHost, RagdollPoseReadsHost,
    RagdollDeathsHost, RuntimeStateSessionClockHost, RuntimeStateConditionReadsHost,
    RuntimeStateSaveContentsHost, RuntimeStateSessionLoadHost, RuntimeStateLiveSeamsHost,
    RuntimeStateReferenceMotionHost, RuntimeStateInventoryFactsHost, StoryAmbientTalkHost,
    StorySocialSearchHost, StorySceneLinesHost, StorySceneCastHost, MenuWorldSettingsApplyHost,
    MenuWorldSkillsRaceHost, MenuWorldNewGameHost, MenuWorldScriptMenusHost,
    MenuWorldTeleportsHost, MenuScreensCraftingDeskHost, MenuScreensGuidesHost,
    MenuScreensGiftListsHost, DragonFlightCandidatesHost, LoadingScreenPresentationHost,
    ActorGraphGraphEventsHost, BenchmarkTourSettingsHost, DialogueMenuSpeechHost,
    LockpickingBoardHost, MountDragonRidingHost, MessageCameraEffectsHost,
    FollowerCommandTasksHost, IdlePlacementHost, PlayerFirstPersonHost, PlayerFaceHost,
    AudioListenerHost, AudioMixHost, CrimeFactionsHost, CrimeJailHost, CrimeActorsHost,
    ProgressionTrainingHost, ProgressionEffectsHost, MapRecordsHost, MapTravelHost, MapQuestsHost,
    DialogueCameraFocusHost, DialogueSpeakersHost, DialogueOutcomesHost, InventoryReadoutsHost,
    InventoryPickpocketHost, InventoryPerksHost, InventoryRecipesHost, InventoryVendorHost,
    InventoryCommandsHost {}

/// The parts of the session scope that take more than one line to build.
protocol GameSessionParts {
    func makePorts() -> any SessionPortSet
    func build(over stage: SessionStage)
    func makeSystemMenu() -> SystemMenuCoordinator
    func makeRaceMenu() -> RaceMenuCoordinator
    func makeMenuScreenCoordinators() -> MenuScreenCoordinators
    func makeSequenceDoors() -> SequenceDoorCoordinator
    func makeNodeControllers() -> NodeControllerCoordinator
    func makeMenuWorld() -> MenuWorldAdapter
    func makeAgentWorld() -> AgentWorldAdapter
    func makeBenchmarkWorld() -> BenchmarkWorldAdapter
    func makeScriptWorld() -> ScriptWorldAdapter
    func makePlayerWorld() -> PlayerWorldAdapter
    func makeNPCAnimation() -> NPCAnimationCoordinator
    func makeIdles() -> IdleCoordinator
    func makeObjectAnimationWorld() -> ObjectAnimationWorldAdapter
    func makeEffectModelPoser() -> EffectModelPoser
    func makeActorGraphs() -> ActorGraphCoordinator
    func makeScenes() -> SceneCoordinator
    func makeStoryManager() -> StoryManagerCoordinator
    func makeHazardWorld() -> HazardWorldAdapter
    func makeTrapControl() -> TrapControlAdapter
    func makeFactionWorld() -> FactionWorldAdapter
    func makeScripts() -> ScriptCoordinator
    func makeInventory() -> InventoryCoordinator
    func makeMagic() -> MagicCoordinator
    func makeEffects() -> EffectsCoordinator
    func makeCombat() -> CombatCoordinator
    func makeFurniture() -> FurnitureCoordinator
    func makeLoadingWorld() -> LoadingScreenWorldAdapter
}
