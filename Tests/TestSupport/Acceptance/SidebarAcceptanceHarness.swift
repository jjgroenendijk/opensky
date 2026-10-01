// The real sidebar and destination registry over one fake provider set, as the
// panel acceptance suites drive them. Readouts are found by accessibility id.

import AppKit
@testable import OpenSky
import Testing

/// One acceptance session: the providers the panels bind to, the real sidebar,
/// and the registry factories that build each destination's panel.
@MainActor
class SidebarAcceptanceHarness {
    let providers = FakeWorldProviders()
    let sidebar = AppSidebarViewController()

    /// Last destination the sidebar reported through the shell's own callback.
    private(set) var selectedDestinationID: String?

    var context: WorldPanelContext {
        WorldPanelContext(providers: providers)
    }

    init() {
        sidebar.onSelect = { [weak self] descriptor in
            self?.selectedDestinationID = descriptor.id
        }
        sidebar.isDestinationOverridden = { [weak self] id in
            guard let self else { return false }
            return DestinationRegistry.destination(id: id)?
                .overrides?.isOverridden(context) ?? false
        }
        _ = sidebar.view
    }

    /// Selects the sidebar row and builds its panel through the registry
    /// factory, as the shell does on selection.
    func select(_ id: String) -> (any InspectorPanel)? {
        sidebar.select(id: id)
        guard
            case let .worldInspector(makePanel) = DestinationRegistry.destination(id: id)?.content
        else { return nil }
        let panel = makePanel(context)
        panel.loadViewIfNeeded()
        refresh(panel)
        return panel
    }

    /// One inspection pass without leaving the 2 Hz ticker running, so the
    /// assertions stay deterministic.
    func refresh(_ panel: any InspectorPanel) {
        panel.startInspecting()
        panel.stopInspecting()
    }

    func overrideIndicatorIsVisible(_ id: String) -> Bool? {
        sidebar.refreshOverrideIndicators()
        return sidebar.overrideIndicatorIsVisible(destinationID: id)
    }

    /// Text of the label carrying `identifier`; nil when no such label is shown.
    func readout(_ identifier: String, in panel: any InspectorPanel) -> String? {
        scriptsReadout(identifier, in: panel.view)
    }
}
