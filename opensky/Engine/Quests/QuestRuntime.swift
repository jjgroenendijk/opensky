// Quest accounting (issue #182, roadmap item 13.2): the mutation API above
// `WorldStateStore` that starts, stops, completes and advances quests.
//
// A thin layer beside the store rather than methods on it, following the M12
// inventory precedent. The store is the generic substrate that knows about
// keys, components, journalling and snapshots and deliberately knows nothing
// about records; quests need `QuestStore` for the record a mutation is
// validated against and for the session-stable key state is filed under,
// neither of which belongs inside it. Everything here writes through
// `WorldStateStore.set(_:for:in:)`, so every mutation lands in the journal, in
// the dirty counts and in the save exactly like a script's `Disable()` does.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window. `@MainActor` only because the store it writes to is.
//
// Nothing is attributed to a cell. A quest is not placed anywhere, so its
// mutations are unattributed exactly as global writes are, and they never drag
// a cell rebuild behind them.
//
// Failure model: every operation that cannot mean what the caller asked throws
// a `QuestError` and writes nothing. An unknown quest, an unknown stage index,
// an unknown objective index and a mutation of a stopped quest are all typed
// failures rather than clamps, because each of them is a caller bug that a
// silent no-op would hide inside a quest that simply never advances.
//
// Papyrus quest script instances, the `Quest` natives and stage fragment
// execution are issue #322 (item 13.3); this layer is the state they will
// mutate, not the script side.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// Reads and mutates quest state on top of a `WorldStateStore`.
@MainActor
struct QuestRuntime {
    let store: WorldStateStore
    /// Plugin-side index every mutation validates against and takes its
    /// session-stable keys from.
    let quests: QuestStore

    // MARK: - Reading

    /// The quest's effective state: its runtime component when it has one, its
    /// re-derived plugin baseline when it does not.
    ///
    /// - Throws: `QuestError.unknownQuest` when no loaded plugin defines it,
    ///   `QuestError.unresolvedQuestKey` when its FormID does not resolve.
    func state(of id: FormID) throws -> QuestRuntimeState {
        let resolved = try resolve(id)
        return state(of: resolved)
    }

    /// Whether the quest has been touched at runtime, as opposed to still
    /// reading straight from plugin data.
    func hasRuntimeState(_ id: FormID) -> Bool {
        guard let key = quests.key(for: id) else { return false }
        return store.component(QuestRuntimeState.self, for: key) != nil
    }

    /// Convenience for a caller holding an editor ID rather than a FormID,
    /// which is what a console line and a sidebar field carry.
    func state(editorID: String) throws -> QuestRuntimeState {
        guard let quest = quests.quest(editorID: editorID) else {
            throw QuestError.unknownQuest(FormID(0))
        }
        return try state(of: quest.formID)
    }

    /// Every quest with runtime state, in `ReferenceKey` total order, paired
    /// with the record it belongs to. For inspection surfaces and for the
    /// journal UI (#184).
    func runtimeQuests() -> [(quest: Quest, state: QuestRuntimeState)] {
        quests.sortedQuests().compactMap { quest in
            guard
                let key = quests.key(for: quest.formID),
                let state = store.component(QuestRuntimeState.self, for: key)
            else {
                return nil
            }
            return (quest: quest, state: state)
        }
    }

    /// Every quest whose effective state is running — runtime states over
    /// plugin baselines — paired with the key its state is filed under, in
    /// editor-ID order.
    ///
    /// This is the set the Papyrus side instantiates scripts for (issue #322):
    /// at session wire-up it is the start-game-enabled quests, and after a
    /// save is restored it is whatever that save recorded.
    func runningQuests() -> [(quest: Quest, key: ReferenceKey)] {
        quests.sortedQuests().compactMap { quest in
            guard let key = quests.key(for: quest.formID) else { return nil }
            let state = store.component(QuestRuntimeState.self, for: key)
                ?? QuestRuntimeState.baseline(for: quest)
            return state.isRunning ? (quest: quest, key: key) : nil
        }
    }

    /// The seam condition functions read quest state through: this session's
    /// runtime states over the plugin baselines.
    func resolution() -> QuestResolution {
        var overrides: [ReferenceKey: QuestRuntimeState] = [:]
        for quest in quests.sortedQuests() {
            guard
                let key = quests.key(for: quest.formID),
                let state = store.component(QuestRuntimeState.self, for: key)
            else {
                continue
            }
            overrides[key] = state
        }
        return QuestResolution(defaults: quests, overrides: overrides)
    }

    // MARK: - Running state

    /// Starts the quest, filling its aliases first. Starting one that already
    /// runs is a no-op that still materializes nothing new, because the write
    /// is skipped when the state is unchanged.
    ///
    /// The alias fill comes first and can refuse the start outright: a quest
    /// whose non-optional alias will not fill "will fail to start" (issue
    /// #183, `QuestAliasFiller`), and a half-started quest whose scripts hold
    /// empty aliases is the state that rule exists to prevent.
    ///
    /// - Throws: `QuestError.aliasFillFailed` when a non-optional alias stayed
    ///   empty, in which case neither the table nor the running flag is written.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func startQuest(_ id: FormID) throws -> QuestRuntimeState {
        let resolved = try resolve(id)
        try fillAliases(of: resolved.quest, key: resolved.key)
        return try apply(to: id) { $0.starting() }
    }

    /// Stops the quest, keeping its reached stages and its completed flag:
    /// stopping is not resetting. Its alias table is *not* kept — an alias is a
    /// live pointer into the world, and the Creation Kit fills one only while
    /// the quest runs. Stopping a quest that is not running is a no-op rather
    /// than a failure — unlike the mutations that only mean something while it
    /// runs, "stop this" is already satisfied.
    ///
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func stopQuest(_ id: FormID) throws -> QuestRuntimeState {
        let resolved = try resolve(id)
        clearAliases(key: resolved.key)
        return try apply(to: id) { $0.stopping() }
    }

    /// Flags the quest completed, leaving it running: `CompleteQuest()` is
    /// documented as flagging completion and nothing else
    /// (<https://ck.uesp.net/wiki/CompleteQuest_-_Quest>). A quest is usually
    /// stopped afterwards by a shut-down stage.
    ///
    /// - Throws: `QuestError.questNotRunning` for a quest that is not running.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func completeQuest(_ id: FormID) throws -> QuestRuntimeState {
        try apply(to: id, requiringRunning: true) { $0.completing() }
    }

    // MARK: - Stages

    /// Records `index` as reached.
    ///
    /// Idempotent per the documented `IsStageDone` semantics: setting a stage
    /// that was already reached changes nothing, and setting a stage lower than
    /// the current one leaves the current stage where it was while making the
    /// lower stage report done
    /// (<https://ck.uesp.net/wiki/GetStageDone_-_Quest>).
    ///
    /// Stage record flags are honoured because they are plain record data: a
    /// stage flagged `startUpStage` starts the quest, which is also the only way
    /// a stage may be set on a quest that is not running, and one flagged
    /// `shutDownStage` stops it afterwards. A stage index may legally appear
    /// more than once in a QUST, so the flags of every matching stage are
    /// unioned rather than taken from the first.
    ///
    /// - Throws: `QuestError.unknownStage` when the quest defines no such
    ///   stage, `QuestError.questNotRunning` when it is not running and the
    ///   stage is not a start-up stage.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func setStage(_ index: UInt16, on id: FormID) throws -> QuestRuntimeState {
        let resolved = try resolve(id)
        let matching = resolved.quest.stages.filter { $0.index == index }
        guard !matching.isEmpty else {
            throw QuestError.unknownStage(quest: id, stage: index)
        }
        let flags = matching.reduce(into: Quest.Stage.Flags()) { $0.formUnion($1.flags) }
        var state = state(of: resolved)
        if !state.isRunning {
            guard flags.contains(.startUpStage) else {
                throw QuestError.questNotRunning(id)
            }
            // A start-up stage starts the quest, so it fills the aliases too,
            // and refuses the whole call the same way `startQuest` does.
            try fillAliases(of: resolved.quest, key: resolved.key)
            state = state.starting()
        }
        state = state.reachingStage(index)
        if flags.contains(.shutDownStage) {
            state = state.stopping()
        }
        store.set(state, for: resolved.key)
        return state
    }

    // MARK: - Objectives

    /// Shows or hides one objective in the journal.
    ///
    /// - Throws: `QuestError.unknownObjective`, `QuestError.questNotRunning`.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func setObjectiveDisplayed(
        _ index: UInt16,
        _ isDisplayed: Bool = true,
        on id: FormID
    ) throws -> QuestRuntimeState {
        try applyToObjective(index, on: id) { $0.settingObjectiveDisplayed(index, isDisplayed) }
    }

    /// Flags one objective completed, or clears that flag.
    ///
    /// - Throws: `QuestError.unknownObjective`, `QuestError.questNotRunning`.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func setObjectiveCompleted(
        _ index: UInt16,
        _ isCompleted: Bool = true,
        on id: FormID
    ) throws -> QuestRuntimeState {
        try applyToObjective(index, on: id) { $0.settingObjectiveCompleted(index, isCompleted) }
    }

    /// Flags one objective failed, or clears that flag.
    ///
    /// - Throws: `QuestError.unknownObjective`, `QuestError.questNotRunning`.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func setObjectiveFailed(
        _ index: UInt16,
        _ isFailed: Bool = true,
        on id: FormID
    ) throws -> QuestRuntimeState {
        try applyToObjective(index, on: id) { $0.settingObjectiveFailed(index, isFailed) }
    }

    // MARK: - Reset

    /// Drops the quest's runtime state, so it re-derives from plugin data
    /// again. The component-level counterpart of `WorldStateStore.reset(_:)`.
    ///
    /// The alias table goes with it: a quest re-deriving from plugin data has
    /// not started, and an alias holds nothing before a start.
    ///
    /// - Returns: true when runtime state was actually removed.
    @discardableResult
    func reset(_ id: FormID) -> Bool {
        guard let key = quests.key(for: id) else { return false }
        let clearedAliases = clearAliases(key: key)
        return store.reset(.quest, for: key) || clearedAliases
    }

    // MARK: - Private

    /// One quest resolved to everything a mutation needs: the record it
    /// validates against and the key its state is filed under.
    private struct ResolvedQuest {
        let quest: Quest
        let key: ReferenceKey
    }

    private func resolve(_ id: FormID) throws -> ResolvedQuest {
        guard let quest = quests.quest(id) else {
            throw QuestError.unknownQuest(id)
        }
        guard let key = quests.key(for: id) else {
            throw QuestError.unresolvedQuestKey(id)
        }
        return ResolvedQuest(quest: quest, key: key)
    }

    private func state(of resolved: ResolvedQuest) -> QuestRuntimeState {
        store.component(QuestRuntimeState.self, for: resolved.key)
            ?? QuestRuntimeState.baseline(for: resolved.quest)
    }

    /// Resolves, optionally insists the quest is running, applies `change` to
    /// the effective state and writes the result.
    private func apply(
        to id: FormID,
        requiringRunning: Bool = false,
        _ change: (QuestRuntimeState) -> QuestRuntimeState
    ) throws -> QuestRuntimeState {
        let resolved = try resolve(id)
        let current = state(of: resolved)
        guard !requiringRunning || current.isRunning else {
            throw QuestError.questNotRunning(id)
        }
        let updated = change(current)
        store.set(updated, for: resolved.key)
        return updated
    }

    /// The three objective mutations differ only in which flag they set, so
    /// they share the index check and the running-quest rule here.
    private func applyToObjective(
        _ index: UInt16,
        on id: FormID,
        _ change: (QuestRuntimeState) -> QuestRuntimeState
    ) throws -> QuestRuntimeState {
        let resolved = try resolve(id)
        guard resolved.quest.objectives.contains(where: { $0.index == index }) else {
            throw QuestError.unknownObjective(quest: id, objective: index)
        }
        return try apply(to: id, requiringRunning: true, change)
    }
}
