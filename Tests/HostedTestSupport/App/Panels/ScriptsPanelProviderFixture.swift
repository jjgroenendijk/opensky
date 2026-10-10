// Recording fake for the World > Scripts seam, shared by the panel and
// registry suites. The snapshot builder is `makeScriptsSnapshot` in
// OpenSkyScriptingTesting.

import AppKit
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface

/// Sends a control's action the way a click would, so a test drives the panel
/// through the same path AppKit does.
@MainActor
func sendScriptsControl(_ control: NSControl) {
    control.sendAction(control.action, to: control.target)
}

/// Depth-first search for a readout label's text by accessibility identifier.
///
/// Reading a readout back by id pins the id contract in a unit test, so a
/// renamed id fails without a UI-test run.
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
    /// Every budget the panel set, in order.
    private(set) var budgetCalls: [Int] = []

    /// Mirrors the engine: the pause write is observable in the next snapshot,
    /// which is what clears or sets the destination's override indicator.
    func setScriptsPaused(_ paused: Bool) {
        setPausedCalls.append(paused)
        scriptsSnapshot = Self.copy(scriptsSnapshot, paused: paused)
    }

    func setScriptInstructionBudget(_ instructions: Int) {
        budgetCalls.append(instructions)
        scriptsSnapshot = Self.copy(scriptsSnapshot, budgetInstructions: instructions)
    }

    func stepScripts(ticks: Int) {
        stepCalls.append(ticks)
    }

    /// Alias tables the fake serves, keyed by editor ID.
    var questAliasTables: [String: ScriptQuestAliasInspection] = [:]

    var questAliasQuestEditorIDs: [String] {
        questAliasTables.keys.sorted()
    }

    func questAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        questAliasTables[editorID]
    }

    /// Rebuilds a snapshot with a new pause flag or budget, keeping everything else.
    private static func copy(
        _ snapshot: ScriptsSnapshot,
        paused: Bool? = nil,
        budgetInstructions: Int? = nil
    ) -> ScriptsSnapshot {
        makeScriptsSnapshot(
            instanceCount: snapshot.instanceCount,
            targetDescription: snapshot.targetDescription,
            targetScripts: snapshot.targetScripts,
            recentEvents: snapshot.recentEvents,
            droppedRecentEventCount: snapshot.droppedRecentEventCount,
            pendingEventCount: snapshot.pendingEventCount,
            isPaused: paused ?? snapshot.isPaused,
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
            budgetInstructions: budgetInstructions ?? snapshot.budgetInstructions,
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
