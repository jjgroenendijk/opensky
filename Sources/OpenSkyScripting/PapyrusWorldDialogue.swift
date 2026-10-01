// Dialogue result-script instances and fragment dispatch, shaped like
// `PapyrusWorldQuests.swift`: keyed by the INFO's `ReferenceKey`, persistent,
// and run through the normal FIFO. Unlike quests, scripts attach lazily when a
// response is chosen, and nothing retires them.
// See docs/engine/dialogue.md and docs/engine/papyrus-quests.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Instantiates the response's result script if needed and enqueues the fragment
    /// for `phase`. A missing script counts as `missingScript`; an undefined function
    /// counts as `undefinedEventFunction`. Neither stops the conversation.
    /// - Returns: the function names enqueued; empty in those cases.
    @discardableResult
    public func queueTopicInfoFragment(
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
        return [fragment.functionName]
    }

    /// Response result scripts holding a live instance.
    public var dialogueInfoCount: Int {
        Set(dialogueInstanceKeys.map(\.reference)).count
    }

    // MARK: - Private

    /// Instantiates one result script, reporting whether an instance exists after.
    /// Idempotent, so script variables persist. The response's VMAD entry is
    /// preferred, because it carries the filled properties; the bare name is the
    /// fallback.
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
