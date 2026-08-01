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
typealias WorldControlProviders = AnimationControlProviding & AudioControlProviding
    & CameraControlProviding & FrameStatsProviding & GrassControlProviding
    & HUDControlProviding & InventoryMenuControlProviding & ItemControlProviding
    & ParticleControlProviding
    & PrecipitationControlProviding
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

    static let all: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "world",
            title: "World",
            section: .world,
            symbolName: "cube.transparent",
            content: .worldInspector { context in
                let panel = WorldPanelViewController()
                panel.cameraProvider = context.providers
                panel.frameStatsProvider = context.providers
                panel.sceneStatsProvider = context.providers
                panel.triggerProvider = context.providers
                // None of the panel's own provider seams carry refocus, so the
                // factory supplies it from the full provider set.
                let providers = context.providers
                panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
                return panel
            },
            overrides: DestinationOverrideActions(
                isOverridden: { CameraSection.isOverridden(provider: $0.providers) },
                resetToDefaults: { CameraSection.resetToDefaults(provider: $0.providers) }
            )
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
                return panel
            },
            overrides: DestinationOverrideActions(
                isOverridden: { HUDElementsSection.isOverridden(provider: $0.providers) },
                resetToDefaults: { context in
                    HUDElementsSection.resetToDefaults(provider: context.providers)
                }
            )
        ),
        DestinationDescriptor(
            id: "systemMenu",
            title: "System Menu",
            section: .world,
            symbolName: "list.bullet.rectangle",
            content: .worldInspector { context in
                let panel = SystemMenuPanelViewController()
                panel.provider = context.providers
                return panel
            },
            overrides: systemMenuOverrides
        ),
        DestinationDescriptor(
            id: "inventoryMenu",
            title: "Inventory Menu",
            section: .world,
            symbolName: "bag",
            content: .worldInspector { context in
                let panel = InventoryMenuPanelViewController()
                panel.provider = context.providers
                return panel
            },
            overrides: inventoryMenuOverrides
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
                },
                resetToDefaults: { context in
                    AudioOutputSection.resetToDefaults(provider: context.providers)
                    AudioSfxSection.resetToDefaults(provider: context.providers)
                    AudioMusicSection.resetToDefaults(provider: context.providers)
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

    private static let environmentOverrides = DestinationOverrideActions(
        isOverridden: { context in
            let providers = context.providers
            return ShadowSection.isOverridden(provider: providers)
                || AnimationSection.isOverridden(provider: providers)
                || WeatherSection.isOverridden(provider: providers)
                || ParticlesSection.isOverridden(provider: providers)
                || PrecipitationSection.isOverridden(provider: providers)
                || GrassSection.isOverridden(provider: providers)
                || TerrainLODSection.isOverridden(provider: providers)
        },
        resetToDefaults: { context in
            let providers = context.providers
            ShadowSection.resetToDefaults(provider: providers)
            AnimationSection.resetToDefaults(provider: providers)
            WeatherSection.resetToDefaults(provider: providers)
            ParticlesSection.resetToDefaults(provider: providers)
            PrecipitationSection.resetToDefaults(provider: providers)
            GrassSection.resetToDefaults(provider: providers)
            TerrainLODSection.resetToDefaults(provider: providers)
        }
    )

    private static let systemMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in
            SystemMenuSection.isOverridden(provider: context.providers)
                || SystemMenuSettingsSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            SystemMenuSection.resetToDefaults(provider: context.providers)
            SystemMenuSettingsSection.resetToDefaults(provider: context.providers)
        }
    )

    private static let inventoryMenuOverrides = DestinationOverrideActions(
        isOverridden: { context in
            InventoryMenuSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            InventoryMenuSection.resetToDefaults(provider: context.providers)
        }
    )

    /// Only the Reset section carries overridden-ness: a dirty reference is the
    /// world deviating from plugin data, which is this destination's notion of
    /// a non-default value, and "Reset all" is what restores it. Inspecting and
    /// saving change no setting.
    private static let runtimeStateOverrides = DestinationOverrideActions(
        isOverridden: { context in
            RuntimeStateResetSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            RuntimeStateResetSection.resetToDefaults(provider: context.providers)
        }
    )

    /// Only the Scheduler section carries overridden-ness: a paused Papyrus VM
    /// is the one thing under this destination that sits away from its default,
    /// and the sidebar's reset resumes it. Stepping leaves no setting behind,
    /// and the other three sections are read-only.
    private static let scriptsOverrides = DestinationOverrideActions(
        isOverridden: { context in
            ScriptSchedulerSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            ScriptSchedulerSection.resetToDefaults(provider: context.providers)
        }
    )

    private static let uiLabOverrides = DestinationOverrideActions(
        isOverridden: { context in
            UILabControlsSection.isOverridden(provider: context.providers)
                || SWFMovieSection.isOverridden(provider: context.providers)
        },
        resetToDefaults: { context in
            UILabControlsSection.resetToDefaults(provider: context.providers)
            SWFMovieSection.resetToDefaults(provider: context.providers)
        }
    )

    /// World-inspector destinations, in order.
    static var worldInspectors: [DestinationDescriptor] {
        all.filter(\.isWorldInspector)
    }

    /// Looks up a destination by id.
    static func destination(id: String) -> DestinationDescriptor? {
        all.first { $0.id == id }
    }
}
