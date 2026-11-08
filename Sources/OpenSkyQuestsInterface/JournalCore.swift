public import OpenSkyFormatsESM

/// One journal quest with its effective state.
nonisolated public struct JournalQuestStatus: Sendable {
    public let quest: Quest
    public let state: QuestRuntimeState

    public init(quest: Quest, state: QuestRuntimeState) {
        self.quest = quest
        self.state = state
    }
}
