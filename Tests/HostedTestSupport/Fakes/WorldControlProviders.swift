// Every panel seam at once, so one fake can stand in for the whole game.

@testable import OpenSky
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCamera
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyEffects
import OpenSkyInventory
import OpenSkyLoading
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyObjectAnimation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyWorld

typealias WorldControlProviders = AINavigationControlProviding
    & AIOverlayControlProviding
    & ActorGraphControlProviding
    & ActorValueControlProviding
    & AgentControlProviding
    & AlchemyControlProviding
    & AnimationControlProviding
    & ArcheryControlProviding
    & AssetCacheControlProviding
    & AudioControlProviding
    & CameraControlProviding
    & CastingControlProviding
    & CinematicCameraControlProviding
    & CombatLoopControlProviding
    & ContainerMenuControlProviding
    & CraftingControlProviding
    & CrimeFactionControlProviding
    & DialogueBranchControlProviding
    & DialogueCameraControlProviding
    & DialogueControlProviding
    & EnchantingControlProviding & ExplosionControlProviding
    & FaceMorphControlProviding
    & FirstPersonControlProviding
    & FrameStatsProviding
    & GrassControlProviding
    & HUDControlProviding
    & HeadAssemblyControlProviding
    & IdleControlProviding
    & ImageSpaceControlProviding
    & ImpactControlProviding
    & InventoryEquipmentControlProviding
    & InventoryMenuControlProviding
    & ItemControlProviding
    & JournalControlProviding
    & LoadingScreenControlProviding
    & LockControlProviding
    & MagicEffectControlProviding
    & MapMenuControlProviding
    & MeleeCombatControlProviding
    & MenuScreensControlProviding
    & MessageControlProviding
    & ObjectAnimationControlProviding
    & ParticleControlProviding
    & PerceptionControlProviding
    & PhysicsControlProviding
    & PlayerLocomotionControlProviding
    & PlayerSettingsControlProviding
    & PrecipitationControlProviding
    & ProgressionControlProviding
    & RaceMenuControlProviding
    & RagdollControlProviding
    & RenderDebugControlProviding
    & RenderPerformanceControlProviding
    & RuntimeStateControlProviding
    & SWFLabControlProviding
    & SceneControlProviding
    & SceneStatsProviding
    & ScriptControlProviding
    & SequenceDoorControlProviding
    & ShadowControlProviding
    & ShoutControlProviding
    & SkillsMenuControlProviding
    & StoryManagerControlProviding
    & SurfaceShadingControlProviding
    & SurvivalModeControlProviding
    & SystemMenuControlProviding
    & TerrainLODControlProviding
    & TerrainShadingControlProviding
    & TitleMenuControlProviding
    & TrapControlProviding
    & TriggerControlProviding
    & UILabControlProviding
    & VisualEffectControlProviding
    & WaterControlProviding
    & WeatherControlProviding
    & WorldLoadReportProviding
    & WorldspaceControlProviding

extension WorldPanelContext {
    init(providers: any WorldControlProviders) {
        self.init(
            game: GamePanelServices(providers: providers),
            features: FeaturePanelServices(providers: providers)
        )
    }
}

extension GamePanelServices {
    init(providers: any WorldControlProviders) {
        self.init(
            aiNavigation: providers,
            aiOverlay: providers,
            alchemy: providers,
            actorValue: providers,
            animation: providers,
            archery: providers,
            assetCache: providers,
            camera: providers,
            casting: providers,
            combatLoop: providers,
            containerMenu: providers,
            crafting: providers,
            crimeFaction: providers,
            dialogueCamera: providers,
            dialogue: providers,
            faceMorph: providers,
            firstPerson: providers,
            frameStats: providers,
            grass: providers,
            inventoryEquipment: providers,
            inventoryMenu: providers,
            item: providers,
            journal: providers,
            lock: providers,
            magicEffect: providers,
            meleeCombat: providers,
            particle: providers,
            perception: providers,
            physics: providers,
            playerLocomotion: providers,
            precipitation: providers,
            progression: providers,
            ragdoll: providers,
            renderDebug: providers,
            renderPerformance: providers,
            sceneStats: providers,
            shadow: providers,
            surfaceShading: providers,
            terrainLOD: providers,
            terrainShading: providers,
            trap: providers,
            trigger: providers,
            water: providers,
            weather: providers,
            worldLoadReport: providers,
            worldspace: providers
        )
    }
}

extension FeaturePanelServices {
    init(providers: any WorldControlProviders) {
        self.init(
            actorGraph: providers,
            agent: providers,
            audio: providers,
            cinematicCamera: providers,
            dialogueBranch: providers,
            enchanting: providers,
            shouts: providers,
            explosion: providers,
            hud: providers,
            headAssembly: providers,
            idle: providers,
            imageSpace: providers,
            impact: providers,
            loadingScreen: providers,
            mapMenu: providers,
            menuScreens: providers,
            message: providers,
            objectAnimation: providers,
            playerSettings: providers,
            raceMenu: providers,
            runtimeState: providers,
            swfLab: providers,
            scene: providers,
            script: providers,
            sequenceDoor: providers,
            skillsMenu: providers,
            storyManager: providers,
            survivalMode: providers,
            systemMenu: providers,
            titleMenu: providers,
            uiLab: providers,
            visualEffect: providers
        )
    }
}
