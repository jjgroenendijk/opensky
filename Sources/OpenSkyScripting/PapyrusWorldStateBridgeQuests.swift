// The session's `PapyrusWorldQuestBridge`. Every change goes through
// `QuestRuntime`. This file adds the script side: start makes scripts, stop
// retires them, and a stage change queues its fragments. Unlike the game,
// `SetStage` and `Start` do not wait (docs/engine/papyrus-quests.md).

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

@MainActor
extension PapyrusWorldStateBridge {
    public func questState(for key: ReferenceKey) throws -> QuestRuntimeState {
        let resolved = try resolveQuest(key)
        return try resolved.runtime.state(of: resolved.quest.formID)
    }

    /// Starts the quest, instantiates its scripts, and sets its start-up stage, so
    /// `Start()` returns with the quest at that stage
    /// (<https://ck.uesp.net/wiki/Start_-_Quest>). A running quest keeps its instances.
    @discardableResult
    public func startQuest(for key: ReferenceKey) throws -> Bool {
        let resolved = try resolveQuest(key)
        let wasRunning = try resolved.runtime.state(of: resolved.quest.formID).isRunning
        let state = try resolved.runtime.startQuest(resolved.quest.formID)
        attachQuestScripts(resolved.quest, key: key)
        guard !wasRunning else { return state.isRunning }
        if let startUp = resolved.quest.stages.first(where: { $0.flags.contains(.startUpStage) }) {
            try setQuestStage(startUp.index, for: key)
        }
        storyNatives.questStarted?(resolved.quest.formID)
        return try resolved.runtime.state(of: resolved.quest.formID).isRunning
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

    @discardableResult
    public func incrementStat(_ name: String, by amount: Int32) -> Bool {
        worldState.incrementMiscStat(name, by: amount)
    }

    public func queryStat(_ name: String) -> Int32 {
        worldState.miscStats.value(name)
    }

    public func completeQuest(for key: ReferenceKey) throws {
        let resolved = try resolveQuest(key)
        try resolved.runtime.completeQuest(resolved.quest.formID)
    }

    /// Sets one stage, then enqueues the fragments of every item whose conditions pass
    /// when it was not reached before. A stopped quest starts, so scripts attach before
    /// fragments queue. A shut-down stage stops the quest but keeps its instances, so
    /// this call's fragments still run; `Stop` retires them.
    @discardableResult
    public func setQuestStage(_ stage: UInt16, for key: ReferenceKey) throws -> Bool {
        let resolved = try resolveQuest(key)
        let id = resolved.quest.formID
        let before = try resolved.runtime.state(of: id)
        let items = passingItems(of: resolved.quest, stage: stage)
        let state = try resolved.runtime.setStage(stage, on: id, items: items)
        if state.isRunning || !before.isRunning {
            attachQuestScripts(resolved.quest, key: key)
        }
        if !before.isStageDone(stage) {
            let chosen = items ?? resolved.quest.stages.first { $0.index == stage }?
                .defaultItems ?? []
            world?.queueQuestFragments(
                of: resolved.quest, stage: stage, key: key,
                logEntries: Set(chosen.map(Int32.init))
            )
        }
        if state.isFailed, !before.isFailed {
            storyNatives.questFailed?(id)
        }
        return true
    }

    /// `FailAllObjectives()`: every shown objective, completed ones too.
    public func failAllQuestObjectives(for key: ReferenceKey) throws {
        let resolved = try resolveQuest(key)
        try resolved.runtime.failAllObjectives(on: resolved.quest.formID)
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

    /// Instantiates one running quest's scripts, as `attachRunningQuestScripts` does
    /// for all. A single start uses it, so it does not revisit every running quest.
    @discardableResult
    public func attachScripts(ofQuest id: FormID) -> Int {
        guard
            let questRuntime,
            let quest = questRuntime.quests.quest(id),
            let key = questRuntime.quests.key(for: id)
        else { return 0 }
        do {
            try questRuntime.fillAliases(of: quest, key: key)
        } catch {
            questAliasFillFailures += 1
        }
        return attachQuestScripts(quest, key: key)
    }

    // MARK: - Aliases

    /// `ForceRefTo` and `Clear`: writes the fill, then moves the alias scripts to the
    /// new reference, so they get `OnInit` there as a fresh fill does.
    public func forceAlias(_ slot: PapyrusAliasSlot, to reference: ReferenceKey?) throws {
        let resolved = try resolveQuest(slot.quest)
        try resolved.runtime.forceAlias(slot.aliasID, to: reference, on: resolved.quest.formID)
        syncAliasScripts(of: slot, resolved)
    }

    /// `ForceLocationTo` and `LocationAlias.Clear`. A location alias carries no scripts
    /// OpenSky attaches, so only the fill changes.
    public func forceLocationAlias(
        _ slot: PapyrusAliasSlot, to location: ResolvedFormID?
    ) throws {
        let resolved = try resolveQuest(slot.quest)
        try resolved.runtime.forceLocationAlias(
            slot.aliasID, to: location, on: resolved.quest.formID
        )
        world?.aliasResolution = resolved.runtime.aliasResolution()
    }

    private func syncAliasScripts(of slot: PapyrusAliasSlot, _ resolved: ResolvedQuestBridge) {
        world?.aliasResolution = resolved.runtime.aliasResolution()
        world?.retireAliasScripts(of: slot)
        if (try? resolved.runtime.state(of: resolved.quest.formID).isRunning) == true {
            attachQuestScripts(resolved.quest, key: slot.quest)
        }
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

    /// Every stage item whose conditions pass: "The script fragments will be run for all
    /// entries where the conditions pass" (<https://ck.uesp.net/wiki/Quest_Stages_Tab>).
    /// Nil without an evaluator.
    func passingItems(of quest: Quest, stage: UInt16) -> [Int]? {
        let entries = quest.stages.first { $0.index == stage }?.logEntries ?? []
        guard var evaluator = sessionNatives.conditionEvaluator?() else { return nil }
        evaluator.context.subject = .player
        evaluator.context.aliasQuest = quest.formID
        evaluator.context.formIDTranslation = questRuntime?.quests.translation(of: quest.formID)
        return entries.indices.filter { evaluator.evaluate(entries[$0].conditions).isTrue }
    }

    /// In the game a quest's scripts exist whether it runs or not, and a persistent
    /// reference keeps its scripts while unloaded. OpenSky attaches them on first use.
    func attachOnUse(_ key: ReferenceKey) -> Bool {
        if attachIdleQuest(key) {
            return true
        }
        guard
            let world, cellLocation(of: key) == nil,
            let placement = references?.pluginPlacement(of: key)
        else { return false }
        let resolver = formIDResolver ?? FormIDResolver(pluginName: "", masters: [])
        return world.attachUnloaded(placement.entry, formIDResolver: resolver) > 0
    }

    /// The scripts `attachOnUse` would attach for `key`, so an attach can load them first.
    func scriptsOfTarget(_ key: ReferenceKey) -> [String] {
        if let quest = questRuntime?.quests.quest(key: key) {
            return world?.attachedScripts(of: quest).map(\.name) ?? []
        }
        guard
            cellLocation(of: key) == nil,
            let entry = references?.pluginPlacement(of: key)?.entry
        else {
            return []
        }
        return entry.scripts.filter { !$0.isRemoved }.map(\.name)
    }

    private func attachIdleQuest(_ key: ReferenceKey) -> Bool {
        guard
            world?.hasDeferredWork(forQuest: key) == false,
            let quest = try? resolveQuest(key).quest, !quest.script.scripts.isEmpty
        else {
            return false
        }
        return attachQuestScripts(quest, key: key, waitsForTargets: false) > 0
    }

    /// A quest's scripts, bound with the master list of the plugin whose record won.
    /// A synthetic session with no resolver binds against an empty master list,
    /// which resolves only same-plugin FormIDs — the same fallback the
    /// reference path takes.
    @discardableResult
    private func attachQuestScripts(
        _ quest: Quest,
        key: ReferenceKey,
        waitsForTargets: Bool = true
    ) -> Int {
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
        return world.attachQuest(
            quest, key: key, formIDResolver: resolver, aliases: aliases,
            waitsForTargets: waitsForTargets
        )
    }
}
