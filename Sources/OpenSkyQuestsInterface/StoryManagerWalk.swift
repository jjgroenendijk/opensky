import Foundation
public import OpenSkyConditions
public import OpenSkyFormatsESM

nonisolated public struct StoryManagerWalk: Equatable, Sendable {
    public let steps: [StoryManagerStep]
    public let startedQuests: [FormID]
    public let tally: ConditionTally

    public init(
        steps: [StoryManagerStep],
        startedQuests: [FormID],
        tally: ConditionTally
    ) {
        self.steps = steps
        self.startedQuests = startedQuests
        self.tally = tally
    }
}

nonisolated public struct StoryManagerStep: Equatable, Sendable {
    public let outcome: StoryNodeOutcome

    public init(
        outcome: StoryNodeOutcome
    ) {
        self.outcome = outcome
    }
}

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
