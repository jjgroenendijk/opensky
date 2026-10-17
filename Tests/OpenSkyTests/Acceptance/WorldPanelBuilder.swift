// Builds a World destination's panel the way the app does, for the panel
// acceptance suites.

import AppKit
@testable import OpenSky
import Testing

enum WorldPanelAcceptanceError: Error {
    case notAWorldInspector
}

/// Builds the panel of World destination `id` through the sidebar model and the
/// registry factory, the path the app takes, rather than constructing it.
@MainActor
func buildWorldPanel<Panel: InspectorPanel>(
    _ id: String,
    title: String? = nil,
    providers: any WorldControlProviders
) throws -> Panel {
    try buildWorldPanel(id, title: title, context: WorldPanelContext(providers: providers))
}

/// Builds the panel against a live game, wired the way the shell wires it.
@MainActor
func buildWorldPanel<Panel: InspectorPanel>(
    _ id: String,
    title: String? = nil,
    game: GameViewController
) throws -> Panel {
    try buildWorldPanel(id, title: title, context: WorldPanelContext(game: game))
}

@MainActor
private func buildWorldPanel<Panel: InspectorPanel>(
    _ id: String,
    title: String?,
    context: WorldPanelContext
) throws -> Panel {
    let worldGroup = try #require(AppSidebarModel.groups().first { $0.section == .world })
    let descriptor = try #require(worldGroup.destinations.first { $0.id == id })
    #expect(descriptor.sidebarIdentifier == "Destination-\(id)")
    if let title {
        #expect(descriptor.title == title)
    }
    guard case let .worldInspector(makePanel) = descriptor.content else {
        Issue.record("World > \(descriptor.title) is not a world inspector")
        throw WorldPanelAcceptanceError.notAWorldInspector
    }
    let panel = try #require(makePanel(context) as? Panel)
    panel.loadViewIfNeeded()
    return panel
}
