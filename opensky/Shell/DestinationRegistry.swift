// Single registration point for main-app sidebar destinations (issue #98).
// Adding a destination = one DestinationDescriptor here; the shell reads this
// list to build the sidebar and content area. Replaces the former four
// touch-points (enum case + stored panel + panel(for:) switch + wireProvider).
// Placement rules + the how-to: docs/tools/app-ui.md.

import AppKit

/// Sidebar grouping. Rows render under their section's group header.
enum SidebarSection: String, CaseIterable {
    case world
    case library

    /// Uppercased group-row title.
    var title: String {
        switch self {
        case .world: "World"
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

/// How a destination fills the content area.
enum DestinationContent {
    /// An inspector panel shown beside the always-live game view.
    case worldInspector(makePanel: @MainActor (WorldPanelContext) -> any InspectorPanel)
    /// A full-content controller that fills the content area (e.g. Asset Browser).
    case fullContent(makeController: @MainActor () -> NSViewController)
}

/// One sidebar destination: its identity, placement, icon, and content.
struct DestinationDescriptor {
    let id: String
    let title: String
    let section: SidebarSection
    /// SF Symbol name for the sidebar row (consumed by the PR 2 shell).
    let symbolName: String
    let content: DestinationContent

    /// Stable accessibility identifier — the UI-test contract. Never change
    /// silently (docs/tools/app-ui.md).
    var sidebarIdentifier: String {
        "WorldDestination-\(id)"
    }

    /// True when this destination shows an inspector panel over the game view.
    var isWorldInspector: Bool {
        if case .worldInspector = content {
            return true
        }
        return false
    }
}

/// The registered destinations, in sidebar order.
enum DestinationRegistry {
    static let all: [DestinationDescriptor] = [
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
            section: .world,
            symbolName: "rectangle.on.rectangle",
            content: .worldInspector { context in
                let panel = UILabPanelViewController()
                panel.provider = context.providers
                return panel
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
