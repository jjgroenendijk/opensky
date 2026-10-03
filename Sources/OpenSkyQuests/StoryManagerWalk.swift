// What one story-manager event did: every node visited, why each quest did or
// did not start, and the condition tally. The sidebar shows it, like the
// dialogue selection trace. See docs/engine/story-manager.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated public enum StoryQuestRejection: Equatable, Sendable {
    /// The quest node names a quest the quest store does not have.
    case unknownQuest
    case alreadyRunning
    /// Hours until reset have not passed since this quest node last started it.
    case resetPending
    /// The quest's own story-manager conditions failed.
    case conditionsFailed
    /// The start was refused, for example a required alias stayed empty.
    case startFailed(String)
    /// The node already started as many quests as it may.
    case limitReached
}

nonisolated public enum StoryNodeOutcome: Equatable, Sendable {
    case conditionsFailed
    case entered
    case questStarted(FormID)
    case questRejected(FormID, StoryQuestRejection)
    /// Max concurrent quests of this node are already running.
    case concurrentLimit
    /// A quest node that started a quest and does not share the event.
    case consumed
}

nonisolated public struct StoryManagerStep: Equatable, Sendable {
    public let node: ResolvedFormID
    public let editorID: String?
    public let depth: Int
    public let outcome: StoryNodeOutcome
}

nonisolated public struct StoryManagerWalk: Equatable, Sendable {
    public let event: StoryEventData
    public let steps: [StoryManagerStep]
    public let startedQuests: [FormID]
    public let tally: ConditionTally
}
