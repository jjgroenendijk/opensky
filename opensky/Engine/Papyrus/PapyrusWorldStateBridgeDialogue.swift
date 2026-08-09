// `DialogueFragmentDispatching` as the session implements it (issue #426): the
// join between a chosen dialogue response and the Papyrus script instances that
// carry its result.
//
// It is the same one-line shape `PapyrusWorldStateBridgeQuests.swift` gives
// `setQuestStage`, and for the same reason: the dialogue layer states *what*
// should run and the world runtime owns *how*, so this file adds no rules of
// its own. What it does add is the seam's failure model — a session with no
// world runtime dispatches nothing and says so by returning an empty list,
// which `DialogueRuntime` counts as an unrun fragment rather than dropping.
//
// The route a quest-stage result takes is worth stating once, because it is the
// whole point of dispatching rather than reaching into quest state directly:
// the response's TIF_ script calls `SetStage` on a `Quest`, which is the M13
// native, which lands in `setQuestStage` next door, which is `QuestRuntime`.
// Dialogue therefore inherits item 13.2's stage rules — the unknown-stage
// failure, the start-up and shut-down flags, the idempotent reached set —
// instead of restating them.

import Foundation

@MainActor
extension PapyrusWorldStateBridge: DialogueFragmentDispatching {
    @discardableResult
    func runTopicInfoFragments(
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
