// Dialogue result-script instances and fragment dispatch for
// `PapyrusWorldRuntime` (issue #426, roadmap item 17.2).
//
// The quest half in `PapyrusWorldQuests.swift` is the model, and the shape is
// deliberately the same one:
//
// * The instance key is the INFO record's session-stable `ReferenceKey` plus
//   the script name. An INFO is a base record that is in no cell, exactly like
//   a QUST, so `PSCR` persistence, `firedOnInit` and the update-timer registry
//   apply with no change at all.
// * The instance is persistent by construction. It is registered in
//   `persistentKeys` and is in no cell's `attachedByCell` set, so no
//   `detach(cell:)` can reach it.
// * The fragment functions go through the normal FIFO, so the per-tick budget,
//   the busy-instance serialization and global event order all apply to a
//   result script exactly as they do to a stage fragment.
//
// Two things differ from quests, both because a response is not a quest:
//
// * The scripts attach lazily, when a response is chosen, rather than at
//   session wire-up. A vanilla load order carries 7,661 INFO result scripts and
//   a session speaks a handful of lines; instantiating every one up front would
//   decode thousands of `.pex` files for nothing.
// * Nothing retires them. A quest has `Stop`; a dialogue response has no
//   counterpart, and the TIF_ scripts the Creation Kit generates hold no state
//   worth clearing between two sayings of the same line. The instance count
//   therefore rises to the number of *distinct* responses a session has run a
//   fragment for, which is bounded by the load order and small in practice.
//
// Documented in docs/engine/dialogue.md and docs/engine/papyrus-vm.md.

import Foundation

extension PapyrusWorldRuntime {
    /// Instantiates the response's generated result script if it is not
    /// instantiated already, and enqueues the fragment function for `phase`.
    ///
    /// A response whose script the library cannot resolve is counted as
    /// `missingScript` and runs nothing; one whose function the script chain
    /// does not define is counted by the dispatcher as `undefinedEventFunction`.
    /// Neither is a fault, and neither stops the conversation.
    ///
    /// - Returns: the function names enqueued, which is empty in both those
    ///   cases and when the response declares no fragment for `phase`.
    @discardableResult
    func queueTopicInfoFragment(
        of info: TopicInfo,
        key: ReferenceKey,
        phase: TopicInfoFragmentPhase,
        formIDResolver: FormIDResolver
    ) -> [String] {
        guard
            let fragment = info.script.infoFragments?.fragment(phase),
            !fragment.scriptName.isEmpty
        else {
            return []
        }
        let target = PapyrusInstanceKey(reference: key, scriptName: fragment.scriptName)
        guard
            attachTopicInfoScript(
                target, declaredBy: info, formIDResolver: formIDResolver
            )
        else {
            return []
        }
        enqueue(PapyrusScriptEvent(
            target: target,
            functionName: fragment.functionName,
            arguments: []
        ))
        dialogueFragmentsQueued += 1
        lastDialogueFragment = "\(fragment.functionName) -> \(target.scriptName)"
        return [fragment.functionName]
    }

    /// Response result scripts holding a live instance.
    var dialogueInfoCount: Int {
        Set(dialogueInstanceKeys.map(\.reference)).count
    }

    // MARK: - Private

    /// Instantiates one result script, reporting whether an instance exists
    /// afterwards. Idempotent: a response said twice runs on the instance the
    /// first saying created, which is what keeps its script variables.
    ///
    /// The generated script normally *also* appears in the response's primary
    /// VMAD list, carrying the properties the Creation Kit filled in for it —
    /// the quest a stage result advances is one of them. The primary entry is
    /// therefore preferred and the bare name is the fallback, exactly as the
    /// quest attach prefers the VMAD script list over the tail's file name. A
    /// result script bound from the fallback has no properties, so a fragment
    /// that reads one sees its compiled default.
    private func attachTopicInfoScript(
        _ target: PapyrusInstanceKey,
        declaredBy info: TopicInfo,
        formIDResolver: FormIDResolver
    ) -> Bool {
        if instancesByKey[target] != nil {
            return true
        }
        let declared = info.script.scripts.first {
            $0.name.lowercased() == target.scriptName.lowercased()
        }
        if let declared, declared.isRemoved {
            skips.note(.removedScript)
            return false
        }
        guard resolveScript(named: target.scriptName) else {
            skips.note(.missingScript)
            return false
        }
        let item = PapyrusAttachItem(
            key: target,
            script: declared
                ?? AttachedScript(name: target.scriptName, flags: [], properties: []),
            isPersistent: true
        )
        guard instantiate(item) else {
            return false
        }
        persistentKeys.insert(target)
        dialogueInstanceKeys.insert(target)
        bind(plan: [item], created: [target], formIDResolver: formIDResolver)
        enqueueOnInitIfNeeded(target)
        return true
    }
}
