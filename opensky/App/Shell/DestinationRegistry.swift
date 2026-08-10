// Single registration point for main-app sidebar destinations (issue #98).
// Adding a destination = one DestinationDescriptor here; the shell reads this
// list to build the sidebar and content area. Replaces the former four
// touch-points (enum case + stored panel + panel(for:) switch + wireProvider).
// Placement rules + the how-to: docs/tools/app-ui.md.

import AppKit

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

/// The live-renderer bridges a world inspector panel may consume. The game
/// controller conforms to all of them, so one value wires every panel.
typealias WorldControlProviders = AINavigationControlProviding
    & AIOverlayControlProviding & ActorValueControlProviding & AnimationControlProviding
    & ArcheryControlProviding & AudioControlProviding
    & CameraControlProviding & CombatLoopControlProviding & ContainerMenuControlProviding
    & DialogueControlProviding
    & FirstPersonControlProviding
    & FrameStatsProviding & GrassControlProviding
    & HUDControlProviding & InventoryEquipmentControlProviding
    & InventoryMenuControlProviding & ItemControlProviding
    & JournalControlProviding
    & MeleeCombatControlProviding
    & ParticleControlProviding
    & PerceptionControlProviding
    & PhysicsControlProviding
    & PlayerLocomotionControlProviding
    & PrecipitationControlProviding & RagdollControlProviding
    & RuntimeStateControlProviding & SWFLabControlProviding & SceneStatsProviding
    & ScriptControlProviding & ShadowControlProviding
    & SystemMenuControlProviding & TerrainLODControlProviding & TriggerControlProviding
    & UILabControlProviding
    & WeatherControlProviding

/// Passed to a world-inspector factory so the panel can wire its providers.
@MainActor
struct WorldPanelContext {
    let providers: any WorldControlProviders
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

    /// The registered destinations, in sidebar order. The three menu
    /// destinations are spliced in from `DestinationRegistryMenus.swift` at the
    /// position they occupy in the sidebar; the registry is still the single
    /// registration point, and the split exists only because this enum body is
    /// at the strict-lint type-length cap.
    static let all: [DestinationDescriptor] = simulationDestinations
        + menuDestinations + sessionDestinations

    private static let simulationDestinations: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "world",
            title: "World",
            section: .world,
            symbolName: "cube.transparent",
            content: .worldInspector { context in
                let panel = WorldPanelViewController()
                panel.cameraProvider = context.providers
                panel.firstPersonProvider = context.providers
                panel.frameStatsProvider = context.providers
                panel.sceneStatsProvider = context.providers
                panel.triggerProvider = context.providers
                // None of the panel's own provider seams carry refocus, so the
                // factory supplies it from the full provider set.
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
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
                panel.provider = context.providers
                panel.cameraProvider = context.providers
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
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
                panel.actorValueProvider = context.providers
                panel.meleeProvider = context.providers
                panel.archeryProvider = context.providers
                panel.ragdollProvider = context.providers
                panel.combatProvider = context.providers
                panel.physicsProvider = context.providers
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
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
                panel.overlayProvider = context.providers
                panel.navigationProvider = context.providers
                panel.perceptionProvider = context.providers
                panel.combatProvider = context.providers
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
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
                panel.provider = context.providers
                panel.weatherProvider = context.providers
                panel.animationProvider = context.providers
                panel.particleProvider = context.providers
                panel.precipitationProvider = context.providers
                panel.grassProvider = context.providers
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
                panel.provider = context.providers
                panel.itemProvider = context.providers
                panel.dialogueProvider = context.providers
                return panel
            },
            overrides: DestinationOverrideActions(
                isOverridden: { context in
                    HUDElementsSection.isOverridden(provider: context.providers)
                        || DialogueSection.isOverridden(provider: context.providers)
                },
                resetToDefaults: { context in
                    HUDElementsSection.resetToDefaults(provider: context.providers)
                    DialogueSection.resetToDefaults(provider: context.providers)
                }
            )
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
                panel.provider = context.providers
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
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
                panel.provider = context.providers
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
                return panel
            },
            overrides: DestinationOverrideActions(
                isOverridden: { context in
                    AudioOutputSection.isOverridden(provider: context.providers)
                        || AudioSfxSection.isOverridden(provider: context.providers)
                        || AudioMusicSection.isOverridden(provider: context.providers)
                        || AudioFootstepsSection.isOverridden(provider: context.providers)
                },
                resetToDefaults: { context in
                    AudioOutputSection.resetToDefaults(provider: context.providers)
                    AudioSfxSection.resetToDefaults(provider: context.providers)
                    AudioMusicSection.resetToDefaults(provider: context.providers)
                    AudioFootstepsSection.resetToDefaults(provider: context.providers)
                }
            )
        ),
        DestinationDescriptor(
            id: "runtimeState",
            title: "Runtime State",
            section: .world,
            symbolName: "clock.arrow.circlepath",
            content: .worldInspector { context in
                let panel = RuntimeStatePanelViewController()
                panel.provider = context.providers
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
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
                panel.provider = context.providers
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
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
                panel.provider = context.providers
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
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
                panel.provider = context.providers
                panel.swfProvider = context.providers
                return panel
            },
            overrides: uiLabOverrides
        ),
        DestinationDescriptor(
            id: "assetBrowser",
            title: "Asset Browser",
            section: .library,
            symbolName: "archivebox",
            content: .fullContent { context in
                let controller = PreviewViewController()
                controller.gameDataRoot = context.gameDataRoot
                controller.startupErrorMessage = context.startupErrorMessage
                return controller
            }
        )
    ]

    /// World-inspector destinations, in order.
    static var worldInspectors: [DestinationDescriptor] {
        all.filter(\.isWorldInspector)
    }

    /// Looks up a destination by id.
    static func destination(id: String) -> DestinationDescriptor? {
        all.first { $0.id == id }
    }
}
