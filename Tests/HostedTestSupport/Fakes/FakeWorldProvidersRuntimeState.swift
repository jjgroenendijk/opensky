// `FakeWorldProviders`' RuntimeStateControlProviding forwarding, with the
// game-clock seam `timeOfDay` uses. Both test targets share the fake, so its
// conformances are shared too (Tests/HostedTestSupport/AGENTS.md).

import AppKit
@testable import OpenSkyWorld
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

    /// In the live app `WorldRenderControls.timeOfDay` calls
    /// `RuntimeStateCoordinator.setGameClockHour(_:)`. Forwarding here keeps the
    /// two surfaces able to disagree, so the M10 gate can check that they do not.
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
