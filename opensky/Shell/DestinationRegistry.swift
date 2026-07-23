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
typealias WorldControlProviders = AnimationControlProviding & GrassControlProviding
    & ParticleControlProviding & PrecipitationControlProviding & ShadowControlProviding
    & TerrainLODControlProviding & UILabControlProviding & WeatherControlProviding

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

/// A full-content controller that can re-apply a changed data root in place
/// (Settings reload) instead of being rebuilt, preserving its loaded state.
@MainActor
protocol FullContentReloadable: NSViewController {
    func reloadFullContent(context: FullContentContext)
}

/// How a destination fills the content area.
enum DestinationContent {
    /// The bare always-live game view, no inspector panel.
    case viewport
    /// An inspector panel shown beside the always-live game view.
    case worldInspector(makePanel: @MainActor (WorldPanelContext) -> any InspectorPanel)
    /// A full-content controller that covers the content area (e.g. Asset
    /// Browser). The game view stays attached underneath and keeps drawing.
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
    /// Selected on launch: the plain live render.
    static let defaultDestinationID = "viewport"

    static let all: [DestinationDescriptor] = [
        DestinationDescriptor(
            id: "viewport",
            title: "Viewport",
            section: .world,
            symbolName: "cube.transparent",
            content: .viewport
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
            }
        ),
        DestinationDescriptor(
            id: "uiLab",
            title: "UI Lab",
            section: .developer,
            symbolName: "rectangle.on.rectangle",
            content: .worldInspector { context in
                let panel = UILabPanelViewController()
                panel.provider = context.providers
                return panel
            }
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
