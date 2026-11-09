// The session ports answer every adapter's host protocol, so each adapter sees
// only the part of the session it reads.

import OpenSkyActorAdapters
import OpenSkyAgentAdapters
import OpenSkyAIAdapters
import OpenSkyCells
import OpenSkyCombatAdapters
import OpenSkyGameData
import OpenSkyInventoryAdapters
import OpenSkyMagicAdapters
import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyProgressionAdapters
import OpenSkyScriptAdapters
import OpenSkySessionAdapters
import OpenSkyStoryAdapters

extension SessionPorts:
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

extension SessionPorts {
    var worldRecords: (any WorldRecordsPort)? {
        worldData
    }
}
