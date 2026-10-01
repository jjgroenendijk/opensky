// The pure rules of the journal readouts: which quests the panel lists and how
// it words an objective. Values in, values out. See docs/engine/journal.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

/// One journal quest with its effective state.
nonisolated public struct JournalQuestStatus: Sendable {
    public let quest: Quest
    public let state: QuestRuntimeState

    public init(quest: Quest, state: QuestRuntimeState) {
        self.quest = quest
        self.state = state
    }
}

public enum JournalCore {
    /// The panel lists the quests that run or ran.
    public static func listed(_ entries: [JournalQuestStatus]) -> [JournalQuestStatus] {
        entries.filter { $0.state.isRunning || $0.state.isCompleted }
    }

    /// Every objective the quest declares, touched or not. An untouched
    /// objective explains a running quest with an empty page.
    public static func objectiveLines(_ entry: JournalQuestStatus) -> [String] {
        entry.quest.objectives.map { objective in
            "\(objective.index) \(objectiveWord(entry.state.objective(objective.index)))"
        }
    }

    public static func objectiveWord(_ objective: QuestObjectiveState) -> String {
        if objective.isFailed {
            "failed"
        } else if objective.isCompleted {
            "completed"
        } else if objective.isDisplayed {
            "displayed"
        } else {
            "untouched"
        }
    }

    public static func declaredStages(of quest: Quest) -> [UInt16] {
        Array(Set(quest.stages.map(\.index))).sorted()
    }
}
