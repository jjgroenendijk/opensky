// `PapyrusWorldQuestBridge` as the session implements it (issue #322): the
// join between the `Quest` natives, the #182 quest state and the #322 script
// instances.
//
// Every mutation goes through `QuestRuntime`, never straight into
// `WorldStateStore`, so the stage rules, the objective rules and the typed
// failures are the ones item 13.2 wrote and this file adds none of its own.
// What it adds is the script side of each mutation: starting a quest
// instantiates its scripts, stopping one retires them, and setting a stage
// runs that stage's fragments.
//
// Documented semantics and the deviations from them, cited from the Creation
// Kit wiki's Quest script reference:
//
// * `bool Function SetCurrentStageID(int aiStage)` (and its `SetStage`
//   wrapper) "attempts to set the quest's current stage. If the stage exists,
//   and was successfully set, the function returns true. Otherwise, the
//   function returns false and the stage is unchanged."
//   (<https://ck.uesp.net/wiki/SetStage_-_Quest>)
// * The same page: the call "is latent and will wait for the quest to start if
//   it has to start the quest. If the stage has any fragments attached to it,
//   the function will also wait for those fragments to finish running before
//   returning", and fragments of several log entries on one stage "will start
//   at the same time, and will NOT wait on the 'previous' item in the list to
//   finish running".
//   **Deviation:** OpenSky's `SetStage` returns as soon as the state is
//   written and the fragments are *enqueued*. Fragments run on a later tick,
//   in fragment-table order, through the one FIFO every other script event
//   uses, so the per-tick budget and per-instance serialization apply to them
//   too. A script that read state back expecting its fragment to have run
//   already sees the pre-fragment value. Making the call latent needs the
//   interpreter to suspend on a world callback, which is not something the
//   M11 suspension machinery does yet.
// * `bool Function Start()` "starts this quest ... is latent and will not
//   return until the quest is actually started (and any start-up stage
//   fragments run)" (<https://ck.uesp.net/wiki/Start_-_Quest>), and
//   `IsRunning` "remains false until the fragment scripts of this stage end
//   their execution" (<https://ck.uesp.net/wiki/IsRunning_-_Quest>).
//   **Deviation:** the same one. `Start` writes the running flag and returns,
//   so `IsRunning` is true immediately.
// * A fragment runs when its stage *transitions* to set. A stage already in
//   the reached set is not re-run, because item 13.2's `setStage` is
//   documented-idempotent (<https://ck.uesp.net/wiki/GetStageDone_-_Quest>)
//   and there is nothing to observe a repeat by. The QUST `allowRepeatedStages`
//   flag, which is what the Creation Kit offers for the repeat case, is
//   decoded and deliberately not consulted: no open documentation states what
//   the engine does with it at `SetStage` time, and guessing would run
//   fragments twice.

import Foundation

@MainActor
extension PapyrusWorldStateBridge: PapyrusWorldQuestBridge {
    func questState(for key: ReferenceKey) throws -> QuestRuntimeState {
        let resolved = try resolveQuest(key)
        return try resolved.runtime.state(of: resolved.quest.formID)
    }

    /// Starts the quest and instantiates its scripts, whose `OnInit` then
    /// fires once ever. A quest that is already running keeps the instances
    /// and the variables it has.
    @discardableResult
    func startQuest(for key: ReferenceKey) throws -> Bool {
        let resolved = try resolveQuest(key)
        let state = try resolved.runtime.startQuest(resolved.quest.formID)
        attachQuestScripts(resolved.quest, key: key)
        return state.isRunning
    }

    /// Stops the quest and retires its scripts. Stopping keeps the reached
    /// stages and the completed flag — item 13.2's rule — while the script
    /// instances and their variables go, so a later `Start` runs `OnInit`
    /// again on fresh ones.
    func stopQuest(for key: ReferenceKey) throws {
        let resolved = try resolveQuest(key)
        try resolved.runtime.stopQuest(resolved.quest.formID)
        world?.detachQuest(key: key)
        // The table went with the stop, so the binding seam must not keep
        // handing the old fills to the next attach.
        world?.aliasResolution = resolved.runtime.aliasResolution()
    }

    func completeQuest(for key: ReferenceKey) throws {
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
    func setQuestStage(_ stage: UInt16, for key: ReferenceKey) throws -> Bool {
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

    func setQuestObjectiveDisplayed(
        _ objective: UInt16, _ isDisplayed: Bool, for key: ReferenceKey
    ) throws {
        let resolved = try resolveQuest(key)
        try resolved.runtime.setObjectiveDisplayed(
            objective, isDisplayed, on: resolved.quest.formID
        )
    }

    func setQuestObjectiveCompleted(
        _ objective: UInt16, _ isCompleted: Bool, for key: ReferenceKey
    ) throws {
        let resolved = try resolveQuest(key)
        try resolved.runtime.setObjectiveCompleted(
            objective, isCompleted, on: resolved.quest.formID
        )
    }

    func setQuestObjectiveFailed(
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
    func attachRunningQuestScripts() -> Int {
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
        let runtime: QuestRuntime
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
