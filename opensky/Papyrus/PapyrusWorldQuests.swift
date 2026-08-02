// Quest script instances and stage-fragment dispatch for
// `PapyrusWorldRuntime` (issue #322, roadmap item 13.3).
//
// A quest is not placed anywhere, so it never attaches or detaches with a
// cell. Everything else about its scripts is the ordinary lifecycle in
// `PapyrusWorldLifecycle.swift`, which is why this file reuses `instantiate`,
// `bind` and `retire` rather than restating them:
//
// * The instance key is the QUST record's session-stable `ReferenceKey` plus
//   the script name, exactly the shape a placed reference uses. `PSCR`
//   persistence, `firedOnInit` and the update-timer registry therefore apply
//   with no change at all.
// * Quest instances are persistent by construction: they are registered in
//   `persistentKeys` and are in no cell's `attachedByCell` set, so no
//   `detach(cell:)` can reach them. Only `stopQuest` retires one.
// * `OnInit` fires once ever per instance through `enqueueOnInitIfNeeded`.
//   `OnCellAttach` and `OnLoad` are deliberately never enqueued: neither
//   event means anything for an object that is in no cell.
//
// Which scripts a quest carries: the QUST VMAD primary script list, plus the
// generated fragment script named by the VMAD tail's file name
// ("QF_<editorID>_<formID>"). The tail's script is included even though
// shipped data normally also lists it as a primary script, because the
// fragment table is the only thing that *guarantees* the fragment script is
// named, and a duplicate costs nothing — both spellings produce the same
// `PapyrusInstanceKey` and the second one is skipped.
//
// Stage fragments: `SetStage` looks the stage up in the #181 fragment table
// and enqueues each matching fragment function on that fragment script's
// instance through the normal FIFO, so the per-tick budget, the busy-instance
// serialization and global event order all apply. Deviations from the
// documented engine behaviour are stated in `PapyrusWorldQuestBridge.swift`,
// beside the call that decides when a fragment runs.
//
// Documented in docs/engine/papyrus-vm.md.

import Foundation

extension PapyrusWorldRuntime {
    /// Instantiates every script `quest` carries and enqueues `OnInit` for the
    /// ones that have never fired it.
    ///
    /// Idempotent: calling it for a quest that already holds instances creates
    /// nothing and enqueues nothing, which is what makes a restarted quest
    /// keep its variables.
    ///
    /// - Parameter key: session-stable identity of the QUST record, which is
    ///   also the identity its script handles resolve to.
    /// - Returns: instances created by this call.
    @discardableResult
    func attachQuest(
        _ quest: Quest,
        key: ReferenceKey,
        formIDResolver: FormIDResolver
    ) -> Int {
        let plan = questAttachPlan(quest, key: key)
        var created: Set<PapyrusInstanceKey> = []
        for item in plan {
            persistentKeys.insert(item.key)
            questInstanceKeys.insert(item.key)
            if instancesByKey[item.key] == nil, instantiate(item) {
                created.insert(item.key)
            }
        }
        bind(plan: plan, created: created, formIDResolver: formIDResolver)
        for item in plan where created.contains(item.key) {
            enqueueOnInitIfNeeded(item.key)
        }
        return created.count
    }

    /// Retires every script instance the quest holds, dropping its variables,
    /// its queued events and its pending timers.
    ///
    /// This is what `Stop` does, and it is the one thing that removes a quest
    /// instance: `Stop` on the real engine shuts the quest's scripts down, and
    /// a later `Start` runs `OnInit` again on the fresh instances. The
    /// `firedOnInit` entry is therefore cleared here as well, which is the one
    /// place in the runtime where it is.
    ///
    /// - Returns: instances retired.
    @discardableResult
    func detachQuest(key: ReferenceKey) -> Int {
        let keys = questInstanceKeys.filter { $0.reference == key }.sorted()
        for instanceKey in keys {
            retire(instanceKey)
            persistentKeys.remove(instanceKey)
            questInstanceKeys.remove(instanceKey)
            firedOnInit.remove(instanceKey)
        }
        return keys.count
    }

    /// Enqueues the fragment functions `quest` attaches to `stage`, in the
    /// file order the fragment table lists them.
    ///
    /// A fragment naming a script the quest holds no instance of is counted as
    /// `missingQuestFragmentInstance` and skipped; a fragment whose function
    /// the script chain does not define is counted by the dispatcher as
    /// `undefinedEventFunction`. Neither is a fault.
    ///
    /// - Returns: events enqueued.
    @discardableResult
    func queueQuestFragments(
        of quest: Quest,
        stage: UInt16,
        key: ReferenceKey
    ) -> Int {
        var queued = 0
        for fragment in quest.fragments where fragment.stageIndex == stage {
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
    var questCount: Int {
        Set(questInstanceKeys.map(\.reference)).count
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
