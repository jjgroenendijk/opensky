// World > Runtime State live bridge, M10.2 game-time and global-variable half
// (issue #166). Split from GameViewControllerRuntimeState.swift so both stay
// inside the file-length limit.
//
// Every clock scrub here is routed through the `GlobalStore` rather than
// written onto `GameClock` directly, whenever the session has loaded plugins.
// That is deliberate: `WorldStateStore.setGlobal(_:formID:defaults:)` redirects
// the five time globals into the clock through `onTimeGlobalWrite`, which moves
// the clock, stores no override, and records one entry on the globals journal
// ring. Scrubbing the clock directly would move time without leaving a trace,
// so the journal readout the milestone gate names would miss exactly the
// mutations the gate is about. The direct path is kept only as the fallback for
// a session with no plugin data, where there is no global to write.
//
// The timescale is not one of those five. `TimeScale` is an ordinary global the
// renderer reads once per frame, so setting it is a plain override write.

import AppKit

extension GameViewController {
    // MARK: Game time

    var runtimeStateClock: RuntimeStateClockSnapshot {
        RuntimeStateClockSnapshot(
            clock: renderer?.gameClock ?? GameClock(),
            timescale: renderer?.currentTimescale ?? GameClock.defaultTimescale,
            isPaused: renderer?.worldSimPaused ?? false
        )
    }

    /// Reuses the `timeOfDay` seam the Environment panel's legacy
    /// `TimeOfDayControl` already writes, so the two surfaces cannot disagree
    /// about the hour and both persist the same setting.
    func setGameClockHour(_ hour: Float) {
        timeOfDay = hour
    }

    /// Writes year, then month, then day. The order matters: `GameClock.setDay`
    /// clamps into the length of the current month, so setting the month first
    /// means 30 Sun's Dawn lands on the 28th of the intended month rather than
    /// of the previous one.
    func setGameClockDate(day: Int, month: Int, year: Int) {
        setTimeGlobal(.gameYear, value: Float(year)) { $0.setYear(year) }
        setTimeGlobal(.gameMonth, value: Float(month)) { $0.setMonth(month) }
        setTimeGlobal(.gameDay, value: Float(day)) { $0.setDay(day) }
    }

    @discardableResult
    func setGameTimescale(_ timescale: Float) -> Bool {
        let clamped = min(
            max(GameClock.timescaleRange.lowerBound, timescale),
            GameClock.timescaleRange.upperBound
        )
        return setGlobalValue(clamped, editorID: GameClock.timescaleEditorID)
    }

    /// One time-global write: through the store when the plugins define the
    /// global, straight onto the clock otherwise.
    private func setTimeGlobal(
        _ global: GameClock.TimeGlobal,
        value: Float,
        fallback: (inout GameClock) -> Void
    ) {
        if
            let globalStore, let id = globalStore.formID(editorID: global.editorID),
            renderer != nil
        {
            worldState.setGlobal(value, formID: id, defaults: globalStore)
            return
        }
        guard var clock = renderer?.gameClock else { return }
        fallback(&clock)
        renderer?.gameClock = clock
    }

    // MARK: Global variables

    var runtimeStateGlobalEditorIDs: [String] {
        if let cached = runtimeState.globalEditorIDs {
            return cached
        }
        let names = (globalStore?.sortedGlobals() ?? []).compactMap(\.editorID)
        runtimeState.globalEditorIDs = names
        return names
    }

    func runtimeStateGlobal(editorID: String) -> RuntimeStateGlobalSnapshot? {
        guard let globalStore, let global = globalStore.global(editorID: editorID) else {
            return nil
        }
        let resolution = runtimeStateGlobalResolution()
        let current = resolution.value(for: global.formID) ?? global.defaultValue
        return RuntimeStateGlobalSnapshot(
            editorID: global.editorID ?? global.formID.description,
            formIDText: global.formID.description,
            typeName: Self.globalTypeName(global.valueType),
            defaultValue: global.defaultValue.value,
            currentValue: current.value,
            isOverridden: resolution.isOverridden(global.formID),
            isConstant: global.isConstant
        )
    }

    @discardableResult
    func setGlobalValue(_ value: Float, editorID: String) -> Bool {
        guard let globalStore, let id = globalStore.formID(editorID: editorID) else {
            return false
        }
        return worldState.setGlobal(value, formID: id, defaults: globalStore)
    }

    @discardableResult
    func resetGlobalValue(editorID: String) -> Bool {
        guard let key = globalStore?.key(editorID: editorID) else { return false }
        return worldState.resetGlobal(for: key)
    }

    func resetAllGlobalOverrides() {
        worldState.resetAllGlobals()
    }

    /// Effective values for this instant: session overrides over plugin
    /// defaults, with the clock projecting the five time globals. Rebuilt per
    /// read because the projection captures the clock as it is now.
    func runtimeStateGlobalResolution() -> GlobalResolution {
        worldState.globalResolution(defaults: globalStore, clock: renderer?.gameClock)
    }

    static func globalTypeName(_ type: Global.ValueType) -> String {
        switch type {
        case .short: "short"
        case .long: "long"
        case .float: "float"
        }
    }
}
