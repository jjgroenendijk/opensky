// Text-replacement tags in dialogue text, such as `<Global=HirelingGold>` in a
// hireling's prompt (<https://ck.uesp.net/wiki/Text_Replacement>). They are read
// against the quest that owns the topic, as journal and message text read theirs.

public import OpenSkyFormatsESM
public import OpenSkyMenusInterface

nonisolated public struct DialogueTextTags: Sendable {
    public static let none = DialogueTextTags(naming: .none) { _ in nil }

    public let naming: QuestAliasNaming
    public let quest: @Sendable (FormID) -> Quest?

    public init(naming: QuestAliasNaming, quest: @escaping @Sendable (FormID) -> Quest?) {
        self.naming = naming
        self.quest = quest
    }

    /// `text` with its tags filled, or as written when `topic` has no known quest.
    public func fill(_ text: String, topic: DialogueTopic?) -> String {
        guard
            text.contains(QuestAliasNaming.tagOpen),
            let id = topic?.owningQuest, let quest = quest(id)
        else { return text }
        return naming.substituting(text, in: quest)
    }
}
