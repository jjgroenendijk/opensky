// One M10 acceptance session — the provider set the panels bind to, the real
// sidebar, the registry factory, and the control-sending helper every step uses.
// Shared by the synthetic M10 and M11 suites in openskyTests and by the
// real-data M10 suites in openskyRealDataTests, so it lives in the folder both
// test targets compile. See openskyTestSupport/AGENTS.md.

import AppKit
import Foundation
@testable import opensky
import Testing

/// One M10.1 acceptance session: the provider set the panel binds to, the real
/// sidebar, and the registry factory that builds the Runtime State panel.
@MainActor
final class M10AcceptanceHarness {
    let providers = FakeWorldProviders()
    let sidebar = AppSidebarViewController()

    /// Last destination the sidebar reported through the shell's own callback.
    private(set) var selectedDestinationID: String?

    var context: WorldPanelContext {
        WorldPanelContext(providers: providers)
    }

    /// The recorder behind every runtime-state call the panel makes.
    var engine: FakeRuntimeStateProvider {
        providers.runtimeState
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

    /// Selects the sidebar row and builds that destination's panel through the
    /// registry factory, exactly as the shell does on selection.
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

    /// Builds the Runtime State panel with the engine already reporting
    /// `snapshot`, which is the state the readouts describe.
    func selectRuntimeState(
        _ snapshot: RuntimeStateSnapshot = .empty
    ) throws -> RuntimeStatePanelViewController {
        engine.runtimeStateSnapshot = snapshot
        return try #require(select("runtimeState") as? RuntimeStatePanelViewController)
    }

    /// Runs one inspection pass (sync controls, refresh readouts) without
    /// leaving the 2 Hz ticker running, so assertions stay deterministic.
    func refresh(_ panel: any InspectorPanel) {
        panel.startInspecting()
        panel.stopInspecting()
    }

    func overrideIndicatorIsVisible(_ id: String) -> Bool? {
        sidebar.refreshOverrideIndicators()
        return sidebar.overrideIndicatorIsVisible(destinationID: id)
    }

    /// Text of the readout label carrying `identifier`, found in the built
    /// panel; nil when no such label is on screen.
    func readout(_ identifier: String, in panel: any InspectorPanel) -> String? {
        Self.label(identifier, in: panel.view)
    }

    /// Replaces only the dirty count, which is how the engine answers a
    /// mutation the panel just requested.
    func reportDirtyCount(_ count: Int) {
        let current = engine.runtimeStateSnapshot
        engine.runtimeStateSnapshot = RuntimeStateSnapshot(
            residentReferenceCount: current.residentReferenceCount,
            dirtyReferenceCount: count,
            journalTail: current.journalTail,
            droppedJournalEntryCount: current.droppedJournalEntryCount,
            nextJournalSequence: current.nextJournalSequence,
            currentTargetDescription: current.currentTargetDescription
        )
    }

    @MainActor
    private static func label(_ identifier: String, in view: NSView) -> String? {
        if view.accessibilityIdentifier() == identifier, let field = view as? NSTextField {
            return field.stringValue
        }
        for subview in view.subviews {
            if let found = label(identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}

@MainActor
func sendM10Control(_ control: NSControl) {
    control.sendAction(control.action, to: control.target)
}
