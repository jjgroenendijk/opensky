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
        if instancesByKey[target] == nil, scriptsLoading([fragment.scriptName]) {
            deferUntilScriptsLoad { [weak self] in
                self?.queueTopicInfoFragment(
                    of: info, key: key, phase: phase, formIDResolver: formIDResolver
                )
            }
            return []
        }
        guard
            attachRecordScript(
                target, declared: info.script.scripts, formIDResolver: formIDResolver
            )
        else {
            return []
        }
        dialogueInstanceKeys.insert(target)
        enqueue(PapyrusScriptEvent(
            target: target,
            functionName: fragment.functionName,
            arguments: []
        ))
        dialogueFragmentsQueued += 1
        return [fragment.functionName]
    }

    /// Instantiates a scene's fragment script if needed and enqueues `functionName`.
    /// Keyed like a result script: the SCEN's `ReferenceKey` plus the script name.
    @discardableResult
    public func queueSceneFragment(
        of scene: Scene,
        key: ReferenceKey,
        scriptName: String,
        functionName: String,
        formIDResolver: FormIDResolver
    ) -> Bool {
        guard !scriptName.isEmpty else { return false }
        let target = PapyrusInstanceKey(reference: key, scriptName: scriptName)
        if instancesByKey[target] == nil, scriptsLoading([scriptName]) {
            deferUntilScriptsLoad { [weak self] in
                self?.queueSceneFragment(
                    of: scene, key: key, scriptName: scriptName, functionName: functionName,
                    formIDResolver: formIDResolver
                )
            }
            return false
        }
        guard
            attachRecordScript(
                target, declared: scene.scriptData.scripts, formIDResolver: formIDResolver
            )
        else {
            return false
        }
        enqueue(PapyrusScriptEvent(target: target, functionName: functionName, arguments: []))
        sceneFragmentsQueued += 1
        return true
    }

    /// Response result scripts holding a live instance.
    public var dialogueInfoCount: Int {
        Set(dialogueInstanceKeys.map(\.reference)).count
    }

    // MARK: - Private

    /// Instantiates one fragment script, reporting whether an instance exists after.
    /// Idempotent, so script variables persist. The record's VMAD entry is
    /// preferred, because it carries the filled properties; the bare name is the
    /// fallback.
    private func attachRecordScript(
        _ target: PapyrusInstanceKey,
        declared scripts: [AttachedScript],
        formIDResolver: FormIDResolver
    ) -> Bool {
        if instancesByKey[target] != nil {
            return true
        }
        let declared = scripts.first {
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
        bind(plan: [item], created: [target], formIDResolver: formIDResolver)
        enqueueOnInitIfNeeded(target)
        return true
    }
}
