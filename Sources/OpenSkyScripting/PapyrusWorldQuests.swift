// Quest script instances and stage-fragment dispatch. Keyed by the QUST's
// `ReferenceKey` plus script name; persistent, retired only by `stopQuest`.
// `OnInit` fires once; cell events never. Alias scripts are keyed by the filled
// reference. Scripts come from the VMAD primary list plus the tail's fragment
// script. Stage fragments run through the normal FIFO.
// See docs/engine/papyrus-quests.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Instantiates every script `quest` carries and enqueues `OnInit` for those
    /// that never fired it. Idempotent, so a restarted quest keeps its variables.
    /// - Parameter key: the QUST's session-stable identity.
    /// - Returns: instances created by this call.
    @discardableResult
    public func attachQuest(
        _ quest: Quest,
        key: ReferenceKey,
        formIDResolver: FormIDResolver,
        aliases: QuestAliasState = .empty
    ) -> Int {
        let names = (quest.script.scripts + fragmentScripts(of: quest)
            + quest.aliasScripts.flatMap(\.scripts)).filter { !$0.isRemoved }.map(\.name)
        if hasDeferredWork(forQuest: key) || scriptsLoading(names) {
            deferUntilScriptsLoad(quest: key) { [weak self] in
                self?.attachQuest(
                    quest, key: key, formIDResolver: formIDResolver, aliases: aliases
                )
            }
            return 0
        }
        let plan = questAttachPlan(quest, key: key)
        var created: Set<PapyrusInstanceKey> = []
        for item in plan {
            persistentKeys.insert(item.key)
            questInstanceKeys.insert(item.key)
            if instancesByKey[item.key] == nil, instantiate(item) {
                created.insert(item.key)
            }
        }
        let aliasPlan = questAliasAttachPlan(quest, aliases: aliases)
        for item in aliasPlan {
            persistentKeys.insert(item.key)
            questAliasInstanceKeys[key, default: []].insert(item.key)
            if instancesByKey[item.key] == nil, instantiate(item) {
                created.insert(item.key)
            }
        }
        bind(plan: plan + aliasPlan, created: created, formIDResolver: formIDResolver)
        for item in plan + aliasPlan where created.contains(item.key) {
            enqueueOnInitIfNeeded(item.key)
        }
        return created.count
    }

    /// Retires every script instance the quest holds, with its variables, events,
    /// and timers, as `Stop` does. Clears `firedOnInit` too, so a later `Start` runs
    /// `OnInit` again.
    /// - Returns: instances retired.
    @discardableResult
    public func detachQuest(key: ReferenceKey) -> Int {
        deferredScriptWork.removeAll { $0.quest == key }
        var keys = questInstanceKeys.filter { $0.reference == key }
        let aliasKeys = questAliasInstanceKeys.removeValue(forKey: key) ?? []
        keys.formUnion(aliasKeys)
        for instanceKey in keys.sorted() {
            retire(instanceKey)
            persistentKeys.remove(instanceKey)
            questInstanceKeys.remove(instanceKey)
            firedOnInit.remove(instanceKey)
        }
        return keys.count
    }

    /// Enqueues the fragment functions `quest` attaches to `stage`, in table order,
    /// only for `logEntry` when given. A missing instance counts as
    /// `missingQuestFragmentInstance`; an undefined function as `undefinedEventFunction`.
    /// - Returns: events enqueued.
    @discardableResult
    public func queueQuestFragments(
        of quest: Quest,
        stage: UInt16,
        key: ReferenceKey,
        logEntry: Int32? = nil
    ) -> Int {
        if hasDeferredWork(forQuest: key) {
            deferUntilScriptsLoad(quest: key) { [weak self] in
                self?.queueQuestFragments(of: quest, stage: stage, key: key, logEntry: logEntry)
            }
            return 0
        }
        var queued = 0
        for fragment in quest.fragments where fragment.stageIndex == stage
            && logEntry.map({ $0 == fragment.logEntryIndex }) ?? true
        {
            let target = PapyrusInstanceKey(
                reference: key, scriptName: fragment.scriptName
            )
            guard instancesByKey[target] != nil else {
                skips.note(.missingQuestFragmentInstance)
                continue
            }
            enqueue(PapyrusScriptEvent(
                target: target,
                functionName: fragment.functionName,
                arguments: []
            ))
            queued += 1
            questFragmentsQueued += 1
            lastQuestFragment = "\(fragment.functionName) -> \(target.scriptName)"
        }
        return queued
    }

    /// Quests holding at least one live script instance.
    public var questCount: Int {
        Set(questInstanceKeys.map(\.reference)).count
    }

    /// Alias script instances live across every running quest.
    public var questAliasInstanceCount: Int {
        questAliasInstanceKeys.values.reduce(0) { $0 + $1.count }
    }

    /// Scripts the quest's filled aliases carry, each instantiated on the reference
    /// in that alias, so it acts like a reference script.
    /// `questAliasInstanceKeys` records the owning quest for `Stop`. An alias section
    /// naming a different quest is skipped.
    private func questAliasAttachPlan(
        _ quest: Quest,
        aliases: QuestAliasState
    ) -> [PapyrusAttachItem] {
        var plan: [PapyrusAttachItem] = []
        var seen: Set<PapyrusInstanceKey> = []
        for section in quest.aliasScripts {
            guard
                section.object.formID == quest.formID,
                let aliasID = section.aliasID,
                aliasID >= 0,
                let reference = aliases.reference(forAlias: UInt32(aliasID))
            else {
                continue
            }
            for script in section.scripts {
                guard !script.isRemoved else {
                    skips.note(.removedScript)
                    continue
                }
                guard resolveScript(named: script.name) else {
                    skips.note(.missingScript)
                    continue
                }
                let instanceKey = PapyrusInstanceKey(
                    reference: reference, scriptName: script.name
                )
                guard seen.insert(instanceKey).inserted else { continue }
                plan.append(PapyrusAttachItem(
                    key: instanceKey, script: script, isPersistent: true
                ))
            }
        }
        return plan
    }

    /// Deterministic plan for one quest's scripts: the primary VMAD list in
    /// file order, then the generated fragment script.
    private func questAttachPlan(
        _ quest: Quest,
        key: ReferenceKey
    ) -> [PapyrusAttachItem] {
        var plan: [PapyrusAttachItem] = []
        var seen: Set<PapyrusInstanceKey> = []
        for script in quest.script.scripts + fragmentScripts(of: quest) {
            guard !script.isRemoved else {
                skips.note(.removedScript)
                continue
            }
            guard resolveScript(named: script.name) else {
                skips.note(.missingScript)
                continue
            }
            let instanceKey = PapyrusInstanceKey(
                reference: key, scriptName: script.name
            )
            guard seen.insert(instanceKey).inserted else { continue }
            plan.append(PapyrusAttachItem(
                key: instanceKey, script: script, isPersistent: true
            ))
        }
        return plan
    }

    /// The generated fragment script as an attachable script with no VMAD
    /// properties of its own. Empty when the quest has no fragment tail, and
    /// also when the tail carries no fragments — a tail that only holds alias
    /// scripts names a file the quest never calls into.
    private func fragmentScripts(of quest: Quest) -> [AttachedScript] {
        guard
            let section = quest.script.questFragments,
            !section.fragments.isEmpty,
            !section.fileName.isEmpty
        else {
            return []
        }
        return [AttachedScript(name: section.fileName, flags: [], properties: [])]
    }
}
