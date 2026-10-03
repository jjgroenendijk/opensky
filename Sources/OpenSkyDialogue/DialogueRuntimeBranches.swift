// Branch scoping of the topics a conversation opens with. A top-level branch
// offers its starting topic; a blocking branch whose starting topic answers is
// the only topic; an exclusive branch the speaker entered acts as blocking.
// Sources and the vanilla counts: docs/engine/dialogue.md.

import Foundation
import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldState

@MainActor
extension DialogueRuntime {
    /// The exclusive branch `speaker` is in, or nil.
    public func exclusiveBranch(of speaker: ReferenceKey) -> FormID? {
        store.component(DialogueBranchState.self, for: speaker)?.exclusiveBranch
    }

    /// Whether a conversation may open on `topic`. A topic without a branch is
    /// offered; vanilla has none, so this keeps mod data that leaves BNAM out.
    public func isBranchEntry(_ topic: DialogueTopic) -> Bool {
        guard let id = topic.owningBranch, let branch = dialogue.branch(id) else { return true }
        return branch.flags.contains(.topLevel) && branch.startingTopic == topic.formID
    }

    /// The starting-topic offer of the blocking branch that answers `speaker`, and
    /// that branch. The speaker's exclusive branch goes first. Then the branch of the
    /// highest-priority quest wins, and ties go to the lower branch FormID.
    func blockingOffer(for speaker: ReferenceKey) -> (offer: DialogueTopicOffer, branch: FormID)? {
        var candidates: [DialogueBranch] = []
        if let exclusive = exclusiveBranch(of: speaker).flatMap({ dialogue.branch($0) }) {
            candidates.append(exclusive)
        }
        candidates += dialogue.blockingBranches()
            .filter { isRunning(quest: $0.quest) }
            .sorted { questPriority($0) == questPriority($1)
                ? $0.formID.rawValue < $1.formID.rawValue
                : questPriority($0) > questPriority($1)
            }
        for branch in candidates {
            guard let id = branch.startingTopic, let topic = dialogue.topic(id) else { continue }
            if let offer = selectTopics([topic], speaker: speaker).offers.first {
                return (offer, branch.formID)
            }
        }
        return nil
    }

    /// The offer a topic gets when branching keeps it out: every response
    /// carries `reason`, and no condition is evaluated.
    func scopedOut(_ topic: DialogueTopic, reason: DialogueRejection) -> DialogueTopicOffer {
        let infos = dialogue.infos(for: topic.formID)
        return DialogueTopicOffer(
            topic: topic.formID,
            info: infos.first?.formID ?? FormID(0),
            considered: infos.map { info in
                DialogueInfoTrace(info: info.formID, outcome: nil, rejection: reason)
            }
        )
    }

    /// Records the exclusive branch a said line belongs to, or leaves it when
    /// the line is from a branch that is not exclusive.
    func noteBranch(ofSaid info: FormID, speaker: ReferenceKey) {
        let branch = dialogue.topic(ofInfo: info)?.owningBranch.flatMap { dialogue.branch($0) }
        if let branch, branch.flags.contains(.exclusive) {
            store.set(DialogueBranchState(exclusiveBranch: branch.formID), for: speaker)
        } else if branch != nil, exclusiveBranch(of: speaker) != nil {
            store.reset(.dialogueBranch, for: speaker)
        }
    }

    private func questPriority(_ branch: DialogueBranch) -> UInt8 {
        branch.quest.flatMap { questStates.quest($0)?.priority } ?? 0
    }
}
