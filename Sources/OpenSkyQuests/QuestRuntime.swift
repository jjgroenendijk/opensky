// Quest accounting: start, stop, complete and advance quests through
// `WorldStateStore.set(_:for:in:)`, so each write reaches the journal and the
// save. A quest has no cell, so its writes never trigger a cell rebuild.
// Each impossible request throws a `QuestError` and writes nothing, because a
// silent no-op would hide a caller bug. See docs/engine/quest-state.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldState

/// Reads and mutates quest state on top of a `WorldStateStore`.
@MainActor
public struct QuestRuntime: QuestAccess {
    public let store: WorldStateStore
    /// Plugin-side index every mutation validates against and takes its
    /// session-stable keys from.
    public let quests: QuestStore
    public let locations: LocationStore?

    public init(store: WorldStateStore, quests: QuestStore, locations: LocationStore? = nil) {
        self.store = store
        self.quests = quests
        self.locations = locations
    }

    // MARK: - Reading

    /// The quest's effective state: its runtime component when it has one, its
    /// re-derived plugin baseline when it does not.
    ///
    /// - Throws: `QuestError.unknownQuest` when no loaded plugin defines it,
    ///   `QuestError.unresolvedQuestKey` when its FormID does not resolve.
    public func state(of id: FormID) throws -> QuestRuntimeState {
        let resolved = try resolve(id)
        return state(of: resolved)
    }

    /// Whether the quest has been touched at runtime, as opposed to still
    /// reading straight from plugin data.
    public func hasRuntimeState(_ id: FormID) -> Bool {
        guard let key = quests.key(for: id) else { return false }
        return store.component(QuestRuntimeState.self, for: key) != nil
    }

    /// Convenience for a caller holding an editor ID rather than a FormID,
    /// which is what a console line and a sidebar field carry.
    public func state(editorID: String) throws -> QuestRuntimeState {
        guard let quest = quests.quest(editorID: editorID) else {
            throw QuestError.unknownQuest(FormID(0))
        }
        return try state(of: quest.formID)
    }

    /// Every quest with runtime state, in `ReferenceKey` order, with its record.
    public func runtimeQuests() -> [(quest: Quest, state: QuestRuntimeState)] {
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

    /// Every quest whose effective state is running, with its key, in editor-ID
    /// order. These are the quests the Papyrus side builds scripts for.
    public func runningQuests() -> [(quest: Quest, key: ReferenceKey)] {
        quests.sortedQuests().compactMap { quest in
            guard let key = quests.key(for: quest.formID) else { return nil }
            let state = store.component(QuestRuntimeState.self, for: key)
                ?? QuestRuntimeState.baseline(for: quest)
            return state.isRunning ? (quest: quest, key: key) : nil
        }
    }

    /// The seam condition functions read quest state through: this session's
    /// runtime states over the plugin baselines.
    public func resolution() -> QuestResolution {
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

    /// Starts the quest, filling its aliases first. A non-optional alias that
    /// stays empty throws `QuestError.aliasFillFailed` and writes nothing.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    public func startQuest(_ id: FormID) throws -> QuestRuntimeState {
        try startQuest(id, event: nil)
    }

    /// - Parameter event: the story-manager event that starts it, for event aliases.
    @discardableResult
    public func startQuest(_ id: FormID, event: StoryEventData?) throws -> QuestRuntimeState {
        let resolved = try resolve(id)
        try fillAliases(of: resolved.quest, key: resolved.key, event: event)
        return try apply(to: id) { $0.starting() }
    }

    /// Starts the quest and sets its start-up stage, as the game does on a real
    /// start. A quest with no start-up stage only starts.
    @discardableResult
    public func startQuestWithStartUpStage(
        _ id: FormID,
        event: StoryEventData?
    ) throws -> QuestRuntimeState {
        let state = try startQuest(id, event: event)
        guard
            let stage = quests.quest(id)?.stages
                .first(where: { $0.flags.contains(.startUpStage) })
        else { return state }
        return try setStage(stage.index, on: id)
    }

    /// Stops the quest. Reached stages and the completed flag stay; the alias table
    /// goes, because an alias is filled only while the quest runs.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    public func stopQuest(_ id: FormID) throws -> QuestRuntimeState {
        let resolved = try resolve(id)
        clearAliases(key: resolved.key)
        return try apply(to: id) { $0.stopping() }
    }

    /// Flags the quest completed and leaves it running, as `CompleteQuest()` does
    /// (<https://ck.uesp.net/wiki/CompleteQuest_-_Quest>).
    /// - Returns: the state as stored afterwards.
    @discardableResult
    public func completeQuest(_ id: FormID) throws -> QuestRuntimeState {
        try apply(to: id, requiringRunning: true) { $0.completing() }
    }

    // MARK: - Stages

    /// Records `index` as reached. A lower stage reports done without moving the
    /// current one (<https://ck.uesp.net/wiki/GetStageDone_-_Quest>). The flags of
    /// every stage with this index count: start-up starts the quest, shut-down stops it.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    public func setStage(_ index: UInt16, on id: FormID) throws -> QuestRuntimeState {
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
    public func setObjectiveDisplayed(
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
    public func setObjectiveCompleted(
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
    public func setObjectiveFailed(
        _ index: UInt16,
        _ isFailed: Bool = true,
        on id: FormID
    ) throws -> QuestRuntimeState {
        try applyToObjective(index, on: id) { $0.settingObjectiveFailed(index, isFailed) }
    }

    // MARK: - Reset

    /// Drops the quest's runtime state and alias table, so it re-derives from
    /// plugin data. Returns true when state was removed.
    @discardableResult
    public func reset(_ id: FormID) -> Bool {
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
