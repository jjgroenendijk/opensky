// `DialogueFragmentDispatching` for the session: joins a chosen response to the
// Papyrus scripts that carry its result. Without a world runtime it returns an
// empty list, which `DialogueRuntime` counts. A quest-stage result reaches
// `QuestRuntime` through the `SetStage` native, so stage rules apply unchanged.

import Foundation
public import OpenSkyDialogueInterface
public import OpenSkyFormatsESM

extension PapyrusWorldStateBridge {
    /// The dialogue and scene fragment dispatcher. A class, because the dialogue
    /// runtime holds its dispatcher as an object; weak, because the bridge owns it.
    public final class Fragments: DialogueFragmentDispatching, SceneFragmentDispatching {
        weak var bridge: PapyrusWorldStateBridge?

        init(bridge: PapyrusWorldStateBridge) {
            self.bridge = bridge
        }

        @discardableResult
        public func runTopicInfoFragments(
            of info: TopicInfo,
            key: ReferenceKey,
            phase: TopicInfoFragmentPhase,
            context: TopicInfoFragmentContext
        ) -> [String] {
            guard let bridge, let world = bridge.world else { return [] }
            return world.queueTopicInfoFragment(
                of: info,
                key: key,
                phase: phase,
                context: context,
                formIDResolver: bridge.formIDResolver ?? FormIDResolver(pluginName: "", masters: [])
            )
        }

        @discardableResult
        public func runSceneFragment(
            of scene: Scene,
            key: ReferenceKey,
            scriptName: String,
            functionName: String
        ) -> Bool {
            guard let bridge, let world = bridge.world else { return false }
            return world.queueSceneFragment(
                of: scene,
                key: key,
                fragment: (scriptName, functionName),
                formIDResolver: bridge.formIDResolver ?? FormIDResolver(pluginName: "", masters: [])
            )
        }
    }
}
