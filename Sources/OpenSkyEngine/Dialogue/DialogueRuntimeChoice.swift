// Choosing a response (issue #426, roadmap item 17.2): what happens once the
// player picks a topic and the winning INFO is delivered.
//
// A satellite of `DialogueRuntime.swift` along a real seam rather than an
// arbitrary line count. That file answers "what is on offer"; this one answers
// "what does taking it do", and the two have different failure models — nothing
// in selection throws, while choosing a response no plugin declares is a typed
// `DialogueError`.
//
// Three things happen, in this order, and the order is the point:
//
// 1. Said-state is written first, so a result script that re-enters selection
//    sees the line it is running as already said. A say-once line that ran its
//    own fragment and only then recorded itself would be offerable from inside
//    its own result.
// 2. The result fragments are dispatched. A quest-stage result reaches
//    `QuestRuntime.setStage` along the route the Creation Kit actually
//    authored: the response's TIF_ script calls `SetStage` on a `Quest`, which
//    is the M13 native, which is `PapyrusWorldStateBridge`, which is
//    `QuestRuntime`. Nothing here knows about quest stages, and that is
//    deliberate — a second, dialogue-only path into quest state would be a
//    second set of stage rules to keep in step with item 13.2's.
// 3. The follow-up topics are selected, after the fragments have been
//    *enqueued*. They run on a later tick through the one FIFO every script
//    event uses, so the links a caller gets back reflect the world before the
//    result script has run. That is the same deviation `SetStage` already
//    documents in `PapyrusWorldStateBridgeQuests.swift`, and it is stated again
//    here because a dialogue tree that branches on a stage its own result just
//    set is exactly where it would be noticed.

import Foundation

/// Where a chosen response's result scripts go.
///
/// A seam rather than a direct call into `PapyrusWorldRuntime` for the reason
/// `PapyrusWorldQuestBridge` is one: the dialogue layer compiles into
/// `openskycli` and is tested without a VM, and a session with no script
/// runtime must still be able to hold a conversation. The conformer in a real
/// session is the Papyrus world bridge.
@MainActor
protocol DialogueFragmentDispatching: AnyObject, Sendable {
    /// Instantiates the response's result script if needed and enqueues the
    /// fragment for `phase`.
    ///
    /// - Returns: the function names enqueued, which is empty when the response
    ///   declares no fragment for that phase or when its script is unavailable.
    @discardableResult
    func runTopicInfoFragments(
        of info: TopicInfo,
        key: ReferenceKey,
        phase: TopicInfoFragmentPhase
    ) -> [String]
}

@MainActor
extension DialogueRuntime {
    /// Applies a chosen response: records it as said, runs its result scripts
    /// and returns the topics it leads to.
    ///
    /// - Parameter speaker: the actor delivering the line, which the follow-up
    ///   selection is evaluated against.
    /// - Throws: `DialogueError.unknownInfo` when no loaded plugin declares the
    ///   response, `DialogueError.unresolvedInfoKey` when its FormID does not
    ///   resolve to a session-stable key, in which case nothing is written.
    @discardableResult
    func choose(_ id: FormID, speaker: ReferenceKey) throws -> DialogueChoice {
        guard let info = dialogue.info(id) else {
            throw DialogueError.unknownInfo(id)
        }
        guard let key = dialogue.key(forInfo: id) else {
            throw DialogueError.unresolvedInfoKey(id)
        }
        let state = saidState(of: id).said()
        store.set(state, for: key)

        var dispatched: [String] = []
        var unrun = 0
        for phase in TopicInfoFragmentPhase.allCases
            where info.script.infoFragments?.fragment(phase) != nil
        {
            guard let fragments else {
                unrun += 1
                continue
            }
            let names = fragments.runTopicInfoFragments(of: info, key: key, phase: phase)
            dispatched.append(contentsOf: names)
            if names.isEmpty {
                unrun += 1
            }
        }

        return DialogueChoice(
            info: id,
            state: state,
            next: topics(linked: info.topicLinks, speaker: speaker),
            endsConversation: info.flags.contains(.goodbye),
            dispatchedFragments: dispatched,
            unrunFragmentCount: unrun
        )
    }
}
