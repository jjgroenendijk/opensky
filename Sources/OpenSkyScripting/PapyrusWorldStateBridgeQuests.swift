// The session's `PapyrusWorldQuestBridge`. Every change goes through
// `QuestRuntime`. This file adds the script side: start makes scripts, stop
// retires them, and a stage change queues its fragments. Unlike the game,
// `SetStage` and `Start` do not wait (docs/engine/papyrus-quests.md).

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

@MainActor
extension PapyrusWorldStateBridge {
    public func questState(for key: ReferenceKey) throws -> QuestRuntimeState {
        let resolved = try resolveQuest(key)
        return try resolved.runtime.state(of: resolved.quest.formID)
    }

    /// Starts the quest and instantiates its scripts, whose `OnInit` then
    /// fires once ever. A quest that is already running keeps the instances
    /// and the variables it has.
    @discardableResult
    public func startQuest(for key: ReferenceKey) throws -> Bool {
        let resolved = try resolveQuest(key)
        let state = try resolved.runtime.startQuest(resolved.quest.formID)
        attachQuestScripts(resolved.quest, key: key)
        return state.isRunning
    }

    /// Stops the quest and retires its scripts. Reached stages and the completed flag
    /// stay; instances go, so a later `Start` runs `OnInit` again.
    public func stopQuest(for key: ReferenceKey) throws {
        let resolved = try resolveQuest(key)
        try resolved.runtime.stopQuest(resolved.quest.formID)
        world?.detachQuest(key: key)
        // The table went with the stop, so the binding seam must not keep
        // handing the old fills to the next attach.
        world?.aliasResolution = resolved.runtime.aliasResolution()
    }

    public func completeQuest(for key: ReferenceKey) throws {
        let resolved = try resolveQuest(key)
        try resolved.runtime.completeQuest(resolved.quest.formID)
    }

    /// Sets one stage, then enqueues its fragments when it was not reached before.
    /// A start-up stage starts the quest, so scripts attach before fragments queue.
    /// A shut-down stage stops the quest but keeps its instances, so this call's
    /// fragments still run; `Stop` retires them.
    @discardableResult
    public func setQuestStage(_ stage: UInt16, for key: ReferenceKey) throws -> Bool {
        let resolved = try resolveQuest(key)
        let id = resolved.quest.formID
        let wasDone = try resolved.runtime.state(of: id).isStageDone(stage)
        let state = try resolved.runtime.setStage(stage, on: id)
        if state.isRunning {
            attachQuestScripts(resolved.quest, key: key)
        }
        if !wasDone {
            world?.queueQuestFragments(of: resolved.quest, stage: stage, key: key)
        }
        return true
    }

    public func setQuestObjectiveDisplayed(
        _ objective: UInt16, _ isDisplayed: Bool, for key: ReferenceKey
    ) throws {
        let resolved = try resolveQuest(key)
        try resolved.runtime.setObjectiveDisplayed(
            objective, isDisplayed, on: resolved.quest.formID
        )
    }

    public func setQuestObjectiveCompleted(
        _ objective: UInt16, _ isCompleted: Bool, for key: ReferenceKey
    ) throws {
        let resolved = try resolveQuest(key)
        try resolved.runtime.setObjectiveCompleted(
            objective, isCompleted, on: resolved.quest.formID
        )
    }

    public func setQuestObjectiveFailed(
        _ objective: UInt16, _ isFailed: Bool, for key: ReferenceKey
    ) throws {
        let resolved = try resolveQuest(key)
        try resolved.runtime.setObjectiveFailed(
            objective, isFailed, on: resolved.quest.formID
        )
    }

    /// Instantiates the scripts of every running quest, at wire-up and after a load.
    /// Aliases fill first when empty. A fill failure here is counted in
    /// `questAliasFillFailures`, and the quest keeps running, because its running
    /// flag came from plugin data.
    /// - Returns: instances created.
    @discardableResult
    public func attachRunningQuestScripts() -> Int {
        guard let questRuntime else { return 0 }
        var created = 0
        for entry in questRuntime.runningQuests() {
            do {
                try questRuntime.fillAliases(of: entry.quest, key: entry.key)
            } catch {
                questAliasFillFailures += 1
            }
            created += attachQuestScripts(entry.quest, key: entry.key)
        }
        return created
    }

    // MARK: - Private

    /// One quest named by a Papyrus handle: the record behind it and the
    /// runtime that mutates it.
    private struct ResolvedQuestBridge {
        let quest: Quest
        let runtime: any QuestAccess
    }

    private func resolveQuest(_ key: ReferenceKey) throws -> ResolvedQuestBridge {
        guard let questRuntime else {
            throw PapyrusQuestBridgeError.noQuestData
        }
        guard let quest = questRuntime.quests.quest(key: key) else {
            throw QuestError.unknownQuest(
                questRuntime.quests.formID(for: key) ?? FormID(0)
            )
        }
        return ResolvedQuestBridge(quest: quest, runtime: questRuntime)
    }

    /// A quest's scripts, bound with the master list of the plugin whose record won.
    /// A synthetic session with no resolver binds against an empty master list,
    /// which resolves only same-plugin FormIDs — the same fallback the
    /// reference path takes.
    @discardableResult
    private func attachQuestScripts(_ quest: Quest, key: ReferenceKey) -> Int {
        guard let world else { return 0 }
        let aliases = questRuntime.flatMap { try? $0.aliasState(of: quest.formID) } ?? .empty
        // The binding seam is refreshed before the attach rather than after,
        // because the properties bound during it are exactly the alias-typed
        // ones this quest just filled.
        world.aliasResolution = questRuntime?.aliasResolution() ?? .empty
        if let newest = aliases.fills.last {
            world.lastQuestAliasFill =
                "\(quest.editorID ?? quest.formID.description)"
                    + "[\(newest.aliasID)] -> \(newest.reference.description)"
        }
        let resolver = questRuntime?.quests.sourceResolver(of: quest.formID)
            ?? formIDResolver
            ?? FormIDResolver(pluginName: "", masters: [])
        return world.attachQuest(quest, key: key, formIDResolver: resolver, aliases: aliases)
    }
}
