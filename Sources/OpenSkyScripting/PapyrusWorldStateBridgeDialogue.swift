// `DialogueFragmentDispatching` for the session: joins a chosen response to the
// Papyrus scripts that carry its result. Without a world runtime it returns an
// empty list, which `DialogueRuntime` counts. A quest-stage result reaches
// `QuestRuntime` through the `SetStage` native, so stage rules apply unchanged.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM

@MainActor
extension PapyrusWorldStateBridge: DialogueFragmentDispatching {
    @discardableResult
    public func runTopicInfoFragments(
        of info: TopicInfo,
        key: ReferenceKey,
        phase: TopicInfoFragmentPhase
    ) -> [String] {
        guard let world else { return [] }
        return world.queueTopicInfoFragment(
            of: info,
            key: key,
            phase: phase,
            formIDResolver: formIDResolver ?? FormIDResolver(pluginName: "", masters: [])
        )
    }
}

@MainActor
extension PapyrusWorldStateBridge: SceneFragmentDispatching {
    @discardableResult
    public func runSceneFragment(
        of scene: Scene,
        key: ReferenceKey,
        scriptName: String,
        functionName: String
    ) -> Bool {
        guard let world else { return false }
        return world.queueSceneFragment(
            of: scene,
            key: key,
            scriptName: scriptName,
            functionName: functionName,
            formIDResolver: formIDResolver ?? FormIDResolver(pluginName: "", masters: [])
        )
    }
}
