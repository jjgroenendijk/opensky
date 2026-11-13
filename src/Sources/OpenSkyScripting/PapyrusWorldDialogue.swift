// Dialogue result-script instances and fragment dispatch, shaped like
// `PapyrusWorldQuests.swift`: keyed by the INFO's `ReferenceKey`, persistent,
// and run through the normal FIFO. Unlike quests, scripts attach lazily when a
// response is chosen, and nothing retires them.
// See docs/engine/dialogue.md and docs/engine/papyrus-quests.md.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime.FragmentRuns {
    /// Instantiates the response's result script if needed and enqueues the fragment
    /// for `phase`. A missing script counts as `missingScript`; an undefined function
    /// counts as `undefinedEventFunction`. Neither stops the conversation.
    /// - Returns: the function names enqueued; empty in those cases.
    @discardableResult
    public func queueTopicInfoFragment(
        of info: TopicInfo,
        key: ReferenceKey,
        phase: TopicInfoFragmentPhase,
        context: TopicInfoFragmentContext = .none,
        formIDResolver: FormIDResolver
    ) -> [String] {
        guard
            let fragment = info.script.infoFragments?.fragment(phase),
            !fragment.scriptName.isEmpty
        else {
            return []
        }
        let target = PapyrusInstanceKey(reference: key, scriptName: fragment.scriptName)
        if
            world.instancesByKey[target] == nil,
            world.lifecycle.scriptsLoading([fragment.scriptName])
        {
            world.lifecycle.deferUntilScriptsLoad { [weak world] in
                world?.fragmentRuns.queueTopicInfoFragment(
                    of: info, key: key, phase: phase, context: context,
                    formIDResolver: formIDResolver
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
        world.dialogueInstanceKeys.insert(target)
        if let quest = context.quest {
            world.fragmentQuests[key] = quest
        }
        world.enqueue(PapyrusScriptEvent(
            target: target,
            functionName: fragment.functionName,
            arguments: context.speaker
                .map { [PapyrusValue.object(world.objectHandle(for: $0))] } ?? []
        ))
        world.dialogueFragmentsQueued += 1
        return [fragment.functionName]
    }

    /// Instantiates a scene's fragment script if needed and enqueues `functionName`.
    /// Keyed like a result script: the SCEN's `ReferenceKey` plus the script name.
    @discardableResult
    public func queueSceneFragment(
        of scene: Scene,
        key: ReferenceKey,
        fragment: (scriptName: String, functionName: String),
        formIDResolver: FormIDResolver
    ) -> Bool {
        let (scriptName, functionName) = fragment
        guard !scriptName.isEmpty else { return false }
        let target = PapyrusInstanceKey(reference: key, scriptName: scriptName)
        if world.instancesByKey[target] == nil, world.lifecycle.scriptsLoading([scriptName]) {
            world.lifecycle.deferUntilScriptsLoad { [weak world] in
                world?.fragmentRuns.queueSceneFragment(
                    of: scene, key: key, fragment: fragment,
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
        if let quest = scene.quest.flatMap({ ReferenceKey.resolve($0, using: formIDResolver) }) {
            world.fragmentQuests[key] = quest
        }
        world.enqueue(PapyrusScriptEvent(target: target, functionName: functionName, arguments: []))
        world.sceneFragmentsQueued += 1
        return true
    }

    /// Response result scripts holding a live instance.
    var dialogueInfoCount: Int {
        Set(world.dialogueInstanceKeys.map(\.reference)).count
    }

    // MARK: - Private

    /// Instantiates one fragment script, reporting whether an instance exists after.
    /// Idempotent, so script variables persist. The record's VMAD entry is
    /// preferred, because it carries the filled properties; the bare name is the
    /// fallback.
    func attachRecordScript(
        _ target: PapyrusInstanceKey,
        declared scripts: [AttachedScript],
        formIDResolver: FormIDResolver
    ) -> Bool {
        if world.instancesByKey[target] != nil {
            return true
        }
        let declared = scripts.first {
            $0.name.lowercased() == target.scriptName.lowercased()
        }
        if let declared, declared.isRemoved {
            world.skips.note(.removedScript)
            return false
        }
        guard world.resolveScript(named: target.scriptName) else {
            world.skips.note(.missingScript)
            return false
        }
        let item = PapyrusAttachItem(
            key: target,
            script: declared
                ?? AttachedScript(name: target.scriptName, flags: [], properties: []),
            isPersistent: true
        )
        guard world.lifecycle.instantiate(item) else {
            return false
        }
        world.persistentKeys.insert(target)
        world.lifecycle.bind(plan: [item], created: [target], formIDResolver: formIDResolver)
        world.enqueueOnInitIfNeeded(target)
        return true
    }
}
