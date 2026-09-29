// The session's `PapyrusWorldQuestBridge`. Every change goes through
// `QuestRuntime`. This file adds the script side: start makes scripts, stop
// retires them, and a stage change queues its fragments. Unlike the game,
// `SetStage` and `Start` do not wait (docs/engine/papyrus-quests.md).

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface

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

    /// Stops the quest and retires its scripts. Stopping keeps the reached
    /// stages and the completed flag — item 13.2's rule — while the script
    /// instances and their variables go, so a later `Start` runs `OnInit`
    /// again on fresh ones.
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

    /// Sets one stage, then enqueues that stage's fragments when the stage was
    /// not already reached.
    ///
    /// A start-up stage starts the quest inside `QuestRuntime.setStage`, so
    /// the scripts are attached here before the fragments are queued — a
    /// fragment on a start-up stage has to find an instance to run on.
    ///
    /// A shut-down stage is the mirror case and is deliberately *not* mirrored:
    /// the quest stops, but its script instances stay. Retiring them here would
    /// delete the fragment this very call just queued, since fragments run on a
    /// later tick. `Stop` is what retires a quest's instances.
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

    /// Instantiates the scripts of every quest the current state reports as
    /// running, which is what a session does once at wire-up and again after a
    /// save is restored.
    ///
    /// Aliases are filled first for a quest that has none yet — a start-game-
    /// enabled quest reaches "running" straight off its DNAM flag without
    /// anything ever calling `Start`, and a restored save may predate the
    /// `QALS` chunk. A quest whose fill *fails* is the one place OpenSky
    /// deviates from the documented "the quest will fail to start" rule: its
    /// running flag came from plugin data rather than from a `Start` call, so
    /// the failure is counted in `questAliasFillFailures` and the quest keeps
    /// running with an empty table rather than being un-started behind the
    /// player's back.
    ///
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

    /// A quest's scripts, bound with the session's master-list resolver. A
    /// synthetic session with no resolver binds against an empty master list,
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
        return world.attachQuest(
            quest,
            key: key,
            formIDResolver: formIDResolver
                ?? FormIDResolver(pluginName: "", masters: []),
            aliases: aliases
        )
    }
}
