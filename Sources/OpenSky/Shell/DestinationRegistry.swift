// Single registration point for main-app sidebar destinations.
// Adding a destination = one DestinationDescriptor here; the shell reads this
// list to build the sidebar and content area. Replaces the former four
// touch-points (enum case + stored panel + panel(for:) switch + wireProvider).
// Placement rules + the how-to: docs/tools/app-ui.md.

import AppKit
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCamera
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyEffects
import OpenSkyGameData
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

/// Sidebar grouping. Rows render under their section's group header, in
/// `allCases` order.
enum SidebarSection: String, CaseIterable {
    case world
    case developer
    case library

    /// Group-row title (the outline uppercases visually via its group style).
    var title: String {
        switch self {
        case .world: "World"
        case .developer: "Developer"
        case .library: "Library"
        }
    }
}

/// Passed to a world-inspector factory so the panel can wire its providers. A field
/// reads through to the group that holds it, such as `context.audio`.
@MainActor
@dynamicMemberLookup
struct WorldPanelContext {
    let game: GamePanelServices
    let features: FeaturePanelServices

    subscript<Value>(dynamicMember path: KeyPath<GamePanelServices, Value>) -> Value {
        game[keyPath: path]
    }

    subscript<Value>(dynamicMember path: KeyPath<FeaturePanelServices, Value>) -> Value {
        features[keyPath: path]
    }
}

/// The seams the game view controller and its render controls answer.
@MainActor
struct GamePanelServices {
    let aiNavigation: any AINavigationControlProviding
    let aiOverlay: any AIOverlayControlProviding
    let actorValue: any ActorValueControlProviding
    let animation: any AnimationControlProviding
    let archery: any ArcheryControlProviding
    let assetCache: any AssetCacheControlProviding
    let camera: any CameraControlProviding
    let casting: any CastingControlProviding
    let combatLoop: any CombatLoopControlProviding
    let containerMenu: any ContainerMenuControlProviding
    let crafting: any CraftingControlProviding
    let crimeFaction: any CrimeFactionControlProviding
    let dialogueCamera: any DialogueCameraControlProviding
    let dialogue: any DialogueControlProviding
    let faceMorph: any FaceMorphControlProviding
    let firstPerson: any FirstPersonControlProviding
    let frameStats: any FrameStatsProviding
    let grass: any GrassControlProviding
    let inventoryEquipment: any InventoryEquipmentControlProviding
    let inventoryMenu: any InventoryMenuControlProviding
    let item: any ItemControlProviding
    let journal: any JournalControlProviding
    let lock: any LockControlProviding
    let magicEffect: any MagicEffectControlProviding
    let meleeCombat: any MeleeCombatControlProviding
    let particle: any ParticleControlProviding
    let perception: any PerceptionControlProviding
    let physics: any PhysicsControlProviding
    let playerLocomotion: any PlayerLocomotionControlProviding
    let precipitation: any PrecipitationControlProviding
    let progression: any ProgressionControlProviding
    let ragdoll: any RagdollControlProviding
    let renderDebug: any RenderDebugControlProviding
    let renderPerformance: any RenderPerformanceControlProviding
    let sceneStats: any SceneStatsProviding
    let shadow: any ShadowControlProviding
    let surfaceShading: any SurfaceShadingControlProviding
    let terrainLOD: any TerrainLODControlProviding
    let terrainShading: any TerrainShadingControlProviding
    let trap: any TrapControlProviding
    let trigger: any TriggerControlProviding
    let water: any WaterControlProviding
    let weather: any WeatherControlProviding
    let worldLoadReport: any WorldLoadReportProviding
    let worldspace: any WorldspaceControlProviding
}

/// The seams feature coordinators and world adapters answer.
@MainActor
struct FeaturePanelServices {
    let agent: any AgentControlProviding
    let audio: any AudioControlProviding
    let cinematicCamera: any CinematicCameraControlProviding
    let dialogueBranch: any DialogueBranchControlProviding
    let explosion: any ExplosionControlProviding
    let hud: any HUDControlProviding
    let headAssembly: any HeadAssemblyControlProviding
    let idle: any IdleControlProviding
    let imageSpace: any ImageSpaceControlProviding
    let impact: any ImpactControlProviding
    let loadingScreen: any LoadingScreenControlProviding
    let mapMenu: any MapMenuControlProviding
    let menuScreens: any MenuScreensControlProviding
    let message: any MessageControlProviding
    let objectAnimation: any ObjectAnimationControlProviding
    let playerSettings: any PlayerSettingsControlProviding
    let raceMenu: any RaceMenuControlProviding
    let runtimeState: any RuntimeStateControlProviding
    let swfLab: any SWFLabControlProviding
    let scene: any SceneControlProviding
    let script: any ScriptControlProviding
    let sequenceDoor: any SequenceDoorControlProviding
    let skillsMenu: any SkillsMenuControlProviding
    let storyManager: any StoryManagerControlProviding
    let survivalMode: any SurvivalModeControlProviding
    let systemMenu: any SystemMenuControlProviding
    let titleMenu: any TitleMenuControlProviding
    let uiLab: any UILabControlProviding
    let visualEffect: any VisualEffectControlProviding
}

/// Passed to a full-content factory (and reload) so the controller can reach
/// the located install without a CLI-side dependency on the app delegate.
struct FullContentContext {
    let gameDataRoot: GameDataRoot?
    let startupErrorMessage: String?
}

/// Provider-backed override queries and resets for one destination. These stay
/// separate from panel construction so unopened destinations remain lazy.
struct DestinationOverrideActions {
    let isOverridden: @MainActor (WorldPanelContext) -> Bool
    let resetToDefaults: @MainActor (WorldPanelContext) -> Void
}

/// A full-content controller that can re-apply a changed data root in place
/// (Settings reload) instead of being rebuilt, preserving its loaded state.
@MainActor
protocol FullContentReloadable: NSViewController {
    func reloadFullContent(context: FullContentContext)
}

/// How a destination fills the content area.
enum DestinationContent {
    /// The bare always-live game view, no inspector panel. No sidebar row uses
    /// this: hiding the inspector column is a View-menu mode over whichever
    /// world destination is selected, not a destination of its own.
    case viewport
    /// An inspector panel shown beside the always-live game view.
    case worldInspector(makePanel: @MainActor (WorldPanelContext) -> any InspectorPanel)
    /// A full-content controller that covers the content area (e.g. Asset
    /// Browser). The game view stays attached underneath but is paused and
    /// hidden while covered, so it costs nothing until the user returns.
    case fullContent(makeController: @MainActor (FullContentContext) -> NSViewController)
}

/// One sidebar destination: its identity, placement, icon, and content.
struct DestinationDescriptor {
    let id: String
    let title: String
    let section: SidebarSection
    /// SF Symbol name for the sidebar row.
    let symbolName: String
    let content: DestinationContent
    let overrides: DestinationOverrideActions?

    init(
        id: String,
        title: String,
        section: SidebarSection,
        symbolName: String,
        content: DestinationContent,
        overrides: DestinationOverrideActions? = nil
    ) {
        self.id = id
        self.title = title
        self.section = section
        self.symbolName = symbolName
        self.content = content
        self.overrides = overrides
    }

    /// Stable accessibility identifier — the UI-test contract. Never change
    /// silently (docs/tools/app-ui.md).
    var sidebarIdentifier: String {
        "Destination-\(id)"
    }

    /// True when this destination shows an inspector panel over the game view.
    var isWorldInspector: Bool {
        if case .worldInspector = content {
            return true
        }
        return false
    }

    /// True when this destination shows the live game view (screenshot +
    /// WASD-refocus apply); false for full-content destinations that cover it.
    var showsGameView: Bool {
        switch content {
        case .viewport, .worldInspector: true
        case .fullContent: false
        }
    }
}

/// The registered destinations, in sidebar order.
enum DestinationRegistry {
    /// Selected on launch: the live render plus its camera/frame/scene readouts.
    static let defaultDestinationID = "world"

    /// The registered destinations, in sidebar order. The menu, progression,
    /// crime, and library destinations are spliced in from the `DestinationRegistry*` files,
    /// which exist only for the type-length cap.
    static let all: [DestinationDescriptor] = simulationDestinations + effectsDestinations
        + progressionDestinations + crimeDestinations + menuDestinations
        + sessionDestinations + libraryDestinations + agentDestinations

    private static let simulationDestinations: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "world",
            title: "World",
            section: .world,
            symbolName: "cube.transparent",
            content: .worldInspector { context in
                let panel = WorldPanelViewController()
                panel.cameraProvider = context.camera
                panel.worldspaceProvider = context.worldspace
                panel.cinematicProvider = context.cinematicCamera
                panel.loadingProvider = context.loadingScreen
                panel.firstPersonProvider = context.firstPerson
                panel.frameStatsProvider = context.frameStats
                panel.worldLoadProvider = context.worldLoadReport
                panel.assetCacheProvider = context.assetCache
                panel.sceneStatsProvider = context.sceneStats
                panel.triggerProvider = context.trigger
                panel.trapProvider = context.trap
                panel.objectAnimationProvider = context.objectAnimation
                panel.sequenceDoorProvider = context.sequenceDoor
                panel.renderDebugProvider = context.renderDebug
                return panel
            },
            overrides: worldOverrides
        ),
        DestinationDescriptor(
            id: "playerLocomotion",
            title: "Player & Locomotion",
            section: .world,
            symbolName: "figure.walk",
            content: .worldInspector { context in
                let panel = PlayerLocomotionPanelViewController()
                panel.provider = context.playerLocomotion
                panel.cameraProvider = context.camera
                return panel
            },
            overrides: playerLocomotionOverrides
        ),
        DestinationDescriptor(
            id: "combatPhysics",
            title: "Combat & Physics",
            section: .world,
            symbolName: "shield.lefthalf.filled",
            content: .worldInspector { context in
                let panel = CombatPhysicsPanelViewController()
                panel.actorValueProvider = context.actorValue
                panel.magicEffectProvider = context.magicEffect
                panel.castingProvider = context.casting
                panel.meleeProvider = context.meleeCombat
                panel.archeryProvider = context.archery
                panel.ragdollProvider = context.ragdoll
                panel.combatProvider = context.combatLoop
                panel.physicsProvider = context.physics
                return panel
            },
            overrides: combatPhysicsOverrides
        ),
        DestinationDescriptor(
            id: "aiNavigation",
            title: "AI & Navigation",
            section: .world,
            symbolName: "point.topleft.down.to.point.bottomright.curvepath",
            content: .worldInspector { context in
                let panel = AINavigationPanelViewController()
                panel.overlayProvider = context.aiOverlay
                panel.navigationProvider = context.aiNavigation
                panel.perceptionProvider = context.perception
                panel.combatProvider = context.combatLoop
                panel.headProvider = context.headAssembly
                panel.idleProvider = context.idle
                return panel
            },
            overrides: aiNavigationOverrides
        ),
        DestinationDescriptor(
            id: "environment",
            title: "Environment",
            section: .world,
            symbolName: "mountain.2",
            content: .worldInspector { context in
                let panel = EnvironmentPanelViewController()
                panel.shadowProvider = context.shadow
                panel.terrainLODProvider = context.terrainLOD
                panel.weatherProvider = context.weather
                panel.animationProvider = context.animation
                panel.particleProvider = context.particle
                panel.precipitationProvider = context.precipitation
                panel.waterProvider = context.water
                panel.terrainProvider = context.terrainShading
                panel.surfaceShadingProvider = context.surfaceShading
                panel.grassProvider = context.grass
                return panel
            },
            overrides: environmentOverrides
        ),
        DestinationDescriptor(
            id: "hudInteraction",
            title: "HUD & Interaction",
            section: .world,
            symbolName: "scope",
            content: .worldInspector { context in
                let panel = HUDInteractionPanelViewController()
                panel.provider = context.hud
                panel.itemProvider = context.item
                panel.messageProvider = context.message
                panel.menuScreensProvider = context.menuScreens
                return panel
            },
            overrides: hudInteractionOverrides
        ),
        DestinationDescriptor(
            id: "dialogueVoice",
            title: "Dialogue & Voice",
            section: .world,
            symbolName: "bubble.left.and.bubble.right",
            content: .worldInspector { context in
                let panel = DialoguePanelViewController()
                panel.dialogueProvider = context.dialogue
                panel.dialogueCameraProvider = context.dialogueCamera
                panel.branchProvider = context.dialogueBranch
                panel.audioProvider = context.audio
                panel.faceMorphProvider = context.faceMorph
                return panel
            },
            overrides: dialogueVoiceOverrides
        )
    ]

    /// Everything after the three menu destinations: what a session carries,
    /// what it saved, what it is running, and the library.
    private static let sessionDestinations: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "inventoryEquipment",
            title: "Inventory & Equipment",
            section: .world,
            symbolName: "backpack",
            content: .worldInspector { context in
                let panel = InventoryEquipmentPanelViewController()
                panel.provider = context.inventoryEquipment
                panel.craftingProvider = context.crafting
                panel.lockProvider = context.lock
                return panel
            },
            overrides: inventoryEquipmentOverrides
        ),
        DestinationDescriptor(
            id: "audio",
            title: "Audio",
            section: .world,
            symbolName: "speaker.wave.2",
            content: .worldInspector { context in
                let panel = AudioPanelViewController()
                panel.provider = context.audio
                return panel
            },
            overrides: audioOverrides
        ),
        DestinationDescriptor(
            id: "runtimeState",
            title: "Runtime State",
            section: .world,
            symbolName: "clock.arrow.circlepath",
            content: .worldInspector { context in
                let panel = RuntimeStatePanelViewController()
                panel.provider = context.runtimeState
                return panel
            },
            overrides: runtimeStateOverrides
        ),
        DestinationDescriptor(
            id: "scripts",
            title: "Scripts",
            section: .world,
            symbolName: "curlybraces",
            content: .worldInspector { context in
                let panel = ScriptsPanelViewController()
                panel.provider = context.script
                return panel
            },
            overrides: scriptsOverrides
        ),
        DestinationDescriptor(
            id: "journal",
            title: "Quests & Journal",
            section: .world,
            symbolName: "book.closed",
            content: .worldInspector { context in
                let panel = JournalPanelViewController()
                panel.provider = context.journal
                panel.sceneProvider = context.scene
                panel.storyProvider = context.storyManager
                return panel
            },
            overrides: journalOverrides
        ),
        DestinationDescriptor(
            id: "uiLab",
            title: "UI Lab",
            section: .developer,
            symbolName: "rectangle.on.rectangle",
            content: .worldInspector { context in
                let panel = UILabPanelViewController()
                panel.provider = context.uiLab
                panel.swfProvider = context.swfLab
                return panel
            },
            overrides: uiLabOverrides
        ),
        DestinationDescriptor(
            id: "renderingPerformance",
            title: "Rendering Performance",
            section: .developer,
            symbolName: "gauge.with.dots.needle.67percent",
            content: .worldInspector { context in
                let panel = RenderingPerformancePanelViewController()
                panel.provider = context.renderPerformance
                return panel
            },
            overrides: renderingPerformanceOverrides
        )
    ]
}

extension DestinationRegistry {
    /// World-inspector destinations, in order.
    static var worldInspectors: [DestinationDescriptor] {
        all.filter(\.isWorldInspector)
    }

    /// Looks up a destination by id.
    static func destination(id: String) -> DestinationDescriptor? {
        all.first { $0.id == id }
    }
}
