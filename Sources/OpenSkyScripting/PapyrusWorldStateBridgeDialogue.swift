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
