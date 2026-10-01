// Game time and globals. With plugins loaded, a clock scrub writes the time
// global, so it is journalled; `WorldStateStore` redirects it into the clock.
// Without plugins it writes the clock directly. `TimeScale` is an ordinary
// global (docs/engine/game-clock.md).

import OpenSkyFormatsESM
import OpenSkyWorldState

extension RuntimeStateCoordinator {
    public var runtimeStateClock: RuntimeStateClockSnapshot {
        RuntimeStateClockSnapshot(
            clock: world?.gameClock ?? GameClock(),
            timescale: world?.timescale ?? GameClock.defaultTimescale,
            isPaused: world?.isWorldSimPaused ?? false
        )
    }

    /// The Environment panel's time-of-day control writes here too, so the two
    /// cannot disagree about the hour.
    public func setGameClockHour(_ hour: Float) {
        if let id = timeGlobalFormID(.gameHour), let globalStore {
            worldState.setGlobal(hour, formID: id, defaults: globalStore)
        } else {
            world?.setTimeOfDay(hour)
        }
        world?.persistTimeOfDay(hour)
    }

    /// Year, then month, then day: `GameClock.setDay` clamps into the current
    /// month, so 30 Sun's Dawn must see the new month first.
    public func setGameClockDate(day: Int, month: Int, year: Int) {
        setTimeGlobal(.gameYear, value: Float(year)) { $0.setYear(year) }
        setTimeGlobal(.gameMonth, value: Float(month)) { $0.setMonth(month) }
        setTimeGlobal(.gameDay, value: Float(day)) { $0.setDay(day) }
    }

    @discardableResult
    public func setGameTimescale(_ timescale: Float) -> Bool {
        setGlobalValue(
            RuntimeStateCore.clampTimescale(timescale), editorID: GameClock.timescaleEditorID
        )
    }

    public var runtimeStateGlobalEditorIDs: [String] {
        if let cached = globalEditorIDs {
            return cached
        }
        let names = (globalStore?.sortedGlobals() ?? []).compactMap(\.editorID)
        globalEditorIDs = names
        return names
    }

    public func runtimeStateGlobal(editorID: String) -> RuntimeStateGlobalSnapshot? {
        guard let globalStore, let global = globalStore.global(editorID: editorID) else {
            return nil
        }
        let resolution = globalResolution()
        let current = resolution.value(for: global.formID) ?? global.defaultValue
        return RuntimeStateGlobalSnapshot(
            editorID: global.editorID ?? global.formID.description,
            formIDText: global.formID.description,
            typeName: RuntimeStateCore.globalTypeName(global.valueType),
            defaultValue: global.defaultValue.value,
            currentValue: current.value,
            isOverridden: resolution.isOverridden(global.formID),
            isConstant: global.isConstant
        )
    }

    @discardableResult
    public func setGlobalValue(_ value: Float, editorID: String) -> Bool {
        guard let globalStore, let id = globalStore.formID(editorID: editorID) else {
            return false
        }
        return worldState.setGlobal(value, formID: id, defaults: globalStore)
    }

    @discardableResult
    public func resetGlobalValue(editorID: String) -> Bool {
        guard let key = globalStore?.key(editorID: editorID) else { return false }
        return worldState.resetGlobal(for: key)
    }

    public func resetAllGlobalOverrides() {
        worldState.resetAllGlobals()
    }

    /// Session overrides over plugin defaults, with the clock projecting the
    /// time globals. Built per read, because the clock moves.
    public func globalResolution() -> GlobalResolution {
        worldState.globalResolution(defaults: globalStore, clock: world?.gameClock)
    }

    /// Nil when there is no clock to redirect into, or no plugin defines it.
    private func timeGlobalFormID(_ global: GameClock.TimeGlobal) -> FormID? {
        guard world?.gameClock != nil else { return nil }
        return globalStore?.formID(editorID: global.editorID)
    }

    private func setTimeGlobal(
        _ global: GameClock.TimeGlobal,
        value: Float,
        fallback: (inout GameClock) -> Void
    ) {
        if let id = timeGlobalFormID(global), let globalStore {
            worldState.setGlobal(value, formID: id, defaults: globalStore)
            return
        }
        guard var clock = world?.gameClock else { return }
        fallback(&clock)
        world?.gameClock = clock
    }
}
