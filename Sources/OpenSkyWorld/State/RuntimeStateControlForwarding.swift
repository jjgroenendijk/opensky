// Lets the app's provider object stand in for its `RuntimeStateCoordinator`, so
// the panel registry keeps one provider value without a forward per member.

public protocol RuntimeStateControlForwarding: RuntimeStateControlProviding {
    var runtimeState: RuntimeStateCoordinator { get }
}

extension RuntimeStateControlForwarding {
    public var runtimeStateSnapshot: RuntimeStateSnapshot {
        runtimeState.runtimeStateSnapshot
    }

    public var lastSaveOutcome: RuntimeStateSaveOutcome {
        runtimeState.lastSaveOutcome
    }

    public var runtimeStateSaveSlots: [String] {
        runtimeState.runtimeStateSaveSlots
    }

    @discardableResult
    public func setReferenceEnabled(_ enabled: Bool, target: RuntimeStateTargetSelector) -> Bool {
        runtimeState.setReferenceEnabled(enabled, target: target)
    }

    @discardableResult
    public func nudgeReferenceTransform(target: RuntimeStateTargetSelector) -> Bool {
        runtimeState.nudgeReferenceTransform(target: target)
    }

    @discardableResult
    public func resetReferenceState(target: RuntimeStateTargetSelector) -> Bool {
        runtimeState.resetReferenceState(target: target)
    }

    public func resetAllReferenceState() {
        runtimeState.resetAllReferenceState()
    }

    public func saveWorldState(slot: String) {
        runtimeState.saveWorldState(slot: slot)
    }

    public func loadWorldState(slot: String) {
        runtimeState.loadWorldState(slot: slot)
    }

    public var runtimeStateClock: RuntimeStateClockSnapshot {
        runtimeState.runtimeStateClock
    }

    public func setGameClockHour(_ hour: Float) {
        runtimeState.setGameClockHour(hour)
    }

    public func setGameClockDate(day: Int, month: Int, year: Int) {
        runtimeState.setGameClockDate(day: day, month: month, year: year)
    }

    @discardableResult
    public func setGameTimescale(_ timescale: Float) -> Bool {
        runtimeState.setGameTimescale(timescale)
    }

    public var runtimeStateGlobalEditorIDs: [String] {
        runtimeState.runtimeStateGlobalEditorIDs
    }

    public func runtimeStateGlobal(editorID: String) -> RuntimeStateGlobalSnapshot? {
        runtimeState.runtimeStateGlobal(editorID: editorID)
    }

    @discardableResult
    public func setGlobalValue(_ value: Float, editorID: String) -> Bool {
        runtimeState.setGlobalValue(value, editorID: editorID)
    }

    @discardableResult
    public func resetGlobalValue(editorID: String) -> Bool {
        runtimeState.resetGlobalValue(editorID: editorID)
    }

    public func resetAllGlobalOverrides() {
        runtimeState.resetAllGlobalOverrides()
    }

    public var runtimeStateConditionSources: [String] {
        runtimeState.runtimeStateConditionSources
    }

    public func evaluateConditions(source: String) -> RuntimeStateConditionReport {
        runtimeState.evaluateConditions(source: source)
    }
}
