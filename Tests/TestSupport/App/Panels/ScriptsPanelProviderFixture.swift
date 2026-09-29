// Recording double for the World > Scripts seam (issue #278), shared by the
// panel suite and by the destination-registry satellite. The snapshot builder
// is `makeScriptsSnapshot` in OpenSkyScriptingTesting.
//
// It lives in its own file for the same reason the Runtime State fixture does:
// stored properties cannot live in an extension, so a fake shared across suites
// has to be one type in one file, and both parent suites sit near the repo
// file-length limit.

import AppKit
@testable import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyScriptingTesting

/// Sends a control's action the way a click would, so a test drives the panel
/// through the same path AppKit does.
@MainActor
func sendScriptsControl(_ control: NSControl) {
    control.sendAction(control.action, to: control.target)
}

/// Depth-first search for a readout label's text by accessibility identifier.
///
/// Reading a readout back by id is what pins the id contract in this repo:
/// `make test-ui` is blocked on this machine (docs/tools/environment.md), so
/// these unit tests are the evidence that the UI-test API exists and carries
/// the value it claims.
@MainActor
func scriptsReadout(_ identifier: String, in view: NSView) -> String? {
    if view.accessibilityIdentifier() == identifier, let field = view as? NSTextField {
        return field.stringValue
    }
    for subview in view.subviews {
        if let found = scriptsReadout(identifier, in: subview) {
            return found
        }
    }
    return nil
}

/// Records what the panel asked the VM to do, so a test can assert on the tick
/// count each button carried rather than on rendered text alone.
@MainActor
final class FakeScriptProvider: ScriptControlProviding {
    var scriptsSnapshot = ScriptsSnapshot.empty

    /// Every pause write the panel requested, in order.
    private(set) var setPausedCalls: [Bool] = []
    /// Tick counts every step request carried, in order.
    private(set) var stepCalls: [Int] = []

    /// Mirrors the engine: the pause write is observable in the next snapshot,
    /// which is what clears or sets the destination's override indicator.
    func setScriptsPaused(_ paused: Bool) {
        setPausedCalls.append(paused)
        scriptsSnapshot = Self.withPaused(scriptsSnapshot, paused)
    }

    func stepScripts(ticks: Int) {
        stepCalls.append(ticks)
    }

    /// Alias tables the fake serves, keyed by editor ID (issue #183).
    var questAliasTables: [String: ScriptQuestAliasInspection] = [:]

    var questAliasQuestEditorIDs: [String] {
        questAliasTables.keys.sorted()
    }

    func questAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        questAliasTables[editorID]
    }

    /// Rebuilds a snapshot with a new pause flag, keeping everything else.
    private static func withPaused(
        _ snapshot: ScriptsSnapshot, _ paused: Bool
    ) -> ScriptsSnapshot {
        makeScriptsSnapshot(
            instanceCount: snapshot.instanceCount,
            targetDescription: snapshot.targetDescription,
            targetScripts: snapshot.targetScripts,
            recentEvents: snapshot.recentEvents,
            droppedRecentEventCount: snapshot.droppedRecentEventCount,
            pendingEventCount: snapshot.pendingEventCount,
            isPaused: paused,
            questInstanceCount: snapshot.questInstanceCount,
            questCount: snapshot.questCount,
            runningQuestCount: snapshot.runningQuestCount,
            questFragmentsQueued: snapshot.questFragmentsQueued,
            lastQuestFragment: snapshot.lastQuestFragment,
            questAliasInstanceCount: snapshot.questAliasInstanceCount,
            filledAliasCount: snapshot.filledAliasCount,
            aliasQuestCount: snapshot.aliasQuestCount,
            questAliasFillFailures: snapshot.questAliasFillFailures,
            lastQuestAliasFill: snapshot.lastQuestAliasFill,
            pendingWaitCount: snapshot.pendingWaitCount,
            pendingTimerCount: snapshot.pendingTimerCount,
            tickCount: snapshot.tickCount,
            budgetEvents: snapshot.budgetEvents,
            budgetInstructions: snapshot.budgetInstructions,
            lastTickSteps: snapshot.lastTickSteps,
            lastTickDispatched: snapshot.lastTickDispatched,
            lastTickQueued: snapshot.lastTickQueued,
            lastTickResumed: snapshot.lastTickResumed,
            lastTickFaulted: snapshot.lastTickFaulted,
            nativeCallTotal: snapshot.nativeCallTotal,
            implementedNativeNameCount: snapshot.implementedNativeNameCount,
            unimplementedNativeTotal: snapshot.unimplementedNativeTotal,
            topUnimplementedNatives: snapshot.topUnimplementedNatives
        )
    }
}
