// Text-replacement tags in dialogue text, such as `<Global=HirelingGold>` in a
// hireling's prompt (<https://ck.uesp.net/wiki/Text_Replacement>). They are read
// against the quest that owns the topic, as journal and message text read theirs. The
// engine fills `<CrimeGold>` and `<BribeCost>` from the speaker (docs/engine/dialogue-menu.md).

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyMenusInterface

nonisolated public struct DialogueTextTags: Sendable {
    public static let none = DialogueTextTags(naming: .none) { _ in nil }

    public let naming: QuestAliasNaming
    /// The speaker's engine tags by name, such as "CrimeGold", already as text.
    public let values: [String: String]
    public let quest: @Sendable (FormID) -> Quest?

    public init(
        naming: QuestAliasNaming, values: [String: String] = [:],
        quest: @escaping @Sendable (FormID) -> Quest?
    ) {
        self.naming = naming
        self.values = values
        self.quest = quest
    }

    /// `text` with its tags filled. A tag nothing can fill stays as written.
    public func fill(_ text: String, topic: DialogueTopic?) -> String {
        guard text.contains(QuestAliasNaming.tagOpen) else { return text }
        var filled = text
        for (name, value) in values {
            filled = filled.replacingOccurrences(of: "<\(name)>", with: value)
        }
        guard let id = topic?.owningQuest, let quest = quest(id) else { return filled }
        return naming.substituting(filled, in: quest)
    }
}
