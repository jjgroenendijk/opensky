// The shared sidebar session plus the Runtime State steps, used by the M10 and
// M11 suites in `OpenSkyTests` and the real-data M10 suites.

import AppKit
import Foundation
@testable import OpenSky
@testable import OpenSkyWorld
import Testing

/// The shared sidebar session, set up for the Runtime State panel.
@MainActor
final class WorldTimeAcceptanceHarness: SidebarAcceptanceHarness {
    /// The recorder behind every runtime-state call the panel makes.
    var engine: FakeRuntimeStateProvider {
        providers.runtimeState
    }

    /// Builds the Runtime State panel with the engine already reporting
    /// `snapshot`, which is the state the readouts describe.
    func selectRuntimeState(
        _ snapshot: RuntimeStateSnapshot = .empty
    ) throws -> RuntimeStatePanelViewController {
        engine.runtimeStateSnapshot = snapshot
        return try #require(select("runtimeState") as? RuntimeStatePanelViewController)
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
}

@MainActor
func sendM10Control(_ control: NSControl) {
    control.sendAction(control.action, to: control.target)
}
