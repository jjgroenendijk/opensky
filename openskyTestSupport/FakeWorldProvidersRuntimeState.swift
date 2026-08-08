// `FakeWorldProviders`' RuntimeStateControlProviding forwarding (M10.1.5),
// including the game-clock seam `timeOfDay` routes through. The fake is shared by
// both test targets, so every conformance it carries has to be too; the suite that
// used to hold this lives on in openskyTests. See openskyTestSupport/AGENTS.md.

import AppKit
@testable import opensky
import Testing

/// Forwards the runtime-state seam to the panel tests' recorder rather than
/// duplicating it, so a registry-level reset and a panel-level button press are
/// observed through the same fake. The conformance itself comes from
/// `WorldControlProviders`, which the class already declares; restating it here
/// would be redundant.
extension FakeWorldProviders {
    var runtimeStateSnapshot: RuntimeStateSnapshot {
        runtimeState.runtimeStateSnapshot
    }

    var lastSaveOutcome: RuntimeStateSaveOutcome {
        runtimeState.lastSaveOutcome
    }

    var runtimeStateSaveSlots: [String] {
        runtimeState.runtimeStateSaveSlots
    }

    @discardableResult
    func setReferenceEnabled(_ enabled: Bool, target: RuntimeStateTargetSelector) -> Bool {
        runtimeState.setReferenceEnabled(enabled, target: target)
    }

    @discardableResult
    func nudgeReferenceTransform(target: RuntimeStateTargetSelector) -> Bool {
        runtimeState.nudgeReferenceTransform(target: target)
    }

    @discardableResult
    func resetReferenceState(target: RuntimeStateTargetSelector) -> Bool {
        runtimeState.resetReferenceState(target: target)
    }

    func resetAllReferenceState() {
        runtimeState.resetAllReferenceState()
    }

    func saveWorldState(slot: String) {
        runtimeState.saveWorldState(slot: slot)
    }

    func loadWorldState(slot: String) {
        runtimeState.loadWorldState(slot: slot)
    }

    var runtimeStateClock: RuntimeStateClockSnapshot {
        runtimeState.runtimeStateClock
    }

    /// The legacy `TimeOfDayControl` under World > Environment writes this
    /// property, and `GameViewController.timeOfDay` and
    /// `GameViewController.setGameClockHour(_:)` are literally the same write in
    /// the live app — the latter calls the former. Forwarding here rather than
    /// storing a second float is what lets the M10 gate assert that the two
    /// surfaces agree instead of asserting it about a fake that cannot disagree.
    var timeOfDay: Float {
        get { runtimeState.runtimeStateClock.hourOfDay }
        set { runtimeState.setGameClockHour(newValue) }
    }

    func setGameClockHour(_ hour: Float) {
        runtimeState.setGameClockHour(hour)
    }

    func setGameClockDate(day: Int, month: Int, year: Int) {
        runtimeState.setGameClockDate(day: day, month: month, year: year)
    }

    @discardableResult
    func setGameTimescale(_ timescale: Float) -> Bool {
        runtimeState.setGameTimescale(timescale)
    }

    var runtimeStateGlobalEditorIDs: [String] {
        runtimeState.runtimeStateGlobalEditorIDs
    }

    func runtimeStateGlobal(editorID: String) -> RuntimeStateGlobalSnapshot? {
        runtimeState.runtimeStateGlobal(editorID: editorID)
    }

    @discardableResult
    func setGlobalValue(_ value: Float, editorID: String) -> Bool {
        runtimeState.setGlobalValue(value, editorID: editorID)
    }

    @discardableResult
    func resetGlobalValue(editorID: String) -> Bool {
        runtimeState.resetGlobalValue(editorID: editorID)
    }

    func resetAllGlobalOverrides() {
        runtimeState.resetAllGlobalOverrides()
    }

    var runtimeStateConditionSources: [String] {
        runtimeState.runtimeStateConditionSources
    }

    func evaluateConditions(source: String) -> RuntimeStateConditionReport {
        runtimeState.evaluateConditions(source: source)
    }
}
