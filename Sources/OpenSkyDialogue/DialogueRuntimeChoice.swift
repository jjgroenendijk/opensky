// Choosing a response. Order: said-state is written first, so a result script
// sees its line as said; the result fragments are queued, reaching quest state
// only through Papyrus natives; the follow-up topics are selected before those
// fragments run, the same deviation `SetStage` documents in
// `PapyrusWorldStateBridgeQuests.swift`.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

@MainActor
extension DialogueRuntime {
    /// Applies a chosen response: records it as said, runs its result scripts, and
    /// returns the topics it leads to.
    /// - Parameter speaker: the actor the follow-up selection is evaluated against.
    /// - Throws: `DialogueError.unknownInfo` or `DialogueError.unresolvedInfoKey`;
    ///   nothing is written then.
    @discardableResult
    public func choose(_ id: FormID, speaker: ReferenceKey) throws -> DialogueChoice {
        guard let info = dialogue.info(id) else {
            throw DialogueError.unknownInfo(id)
        }
        guard let key = dialogue.key(forInfo: id) else {
            throw DialogueError.unresolvedInfoKey(id)
        }
        let state = saidState(of: id).said()
        store.set(state, for: key)
        noteBranch(ofSaid: id, speaker: speaker)

        let quest = dialogue.topic(ofInfo: id)?.owningQuest
            .flatMap { ReferenceKey.resolve($0, using: dialogue.resolver) }
        let context = TopicInfoFragmentContext(speaker: speaker, quest: quest)
        var dispatched: [String] = []
        var unrun = 0
        for phase in TopicInfoFragmentPhase.allCases
            where info.script.infoFragments?.fragment(phase) != nil
        {
            guard let fragments else {
                unrun += 1
                continue
            }
            let names = fragments.runTopicInfoFragments(
                of: info, key: key, phase: phase, context: context
            )
            dispatched.append(contentsOf: names)
            if names.isEmpty {
                unrun += 1
            }
        }

        return DialogueChoice(
            next: topics(linked: info.topicLinks, speaker: speaker),
            endsConversation: info.flags.contains(.goodbye),
            dispatchedFragments: dispatched,
            unrunFragmentCount: unrun
        )
    }
}
