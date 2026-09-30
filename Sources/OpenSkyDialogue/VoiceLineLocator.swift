// Turns a dialogue response plus a speaker's voice type into the archive path of
// its recording, walking the records for the strings `VoiceFilePath` needs.
// Quest lookup uses `ReferenceKey`, because a topic may belong to a quest in a
// master. A miss gives a wrong path, which `DialogueVoice` reports.
// See docs/formats/fuz.md and docs/engine/audio-decoding.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One recorded response of one INFO.
nonisolated public struct VoiceLine: Equatable, Sendable {
    /// Canonical VFS key of the `.fuz` file.
    public let path: String
}

/// One derived voice file name beside the editor IDs it came from. The pair is
/// what makes a name-derivation sweep's mismatch report actionable: a name that
/// does not match tells you nothing on its own about which half of the rule is
/// wrong.
nonisolated public struct VoiceFileNameDerivation: Equatable, Sendable {
    public let name: String
    public let questEditorID: String?
    public let topicEditorID: String?
}

nonisolated public struct VoiceLineLocator: Sendable {
    public let dialogue: DialogueStore
    /// Lowercased plugin file name -> that plugin's QUST index. A topic's
    /// owning quest is looked up here by session-stable key.
    private let questStores: [String: QuestStore]

    public init(dialogue: DialogueStore, quests: QuestStore?) {
        self.init(
            dialogue: dialogue,
            questStores: quests.map { [$0.resolver.pluginName.lowercased(): $0] } ?? [:]
        )
    }

    public init(dialogue: DialogueStore, questStores: [String: QuestStore]) {
        self.dialogue = dialogue
        self.questStores = questStores
    }

    /// File name of the plugin whose records these are, which is also the
    /// directory name under `sound\voice\`.
    public var pluginName: String {
        dialogue.resolver.pluginName
    }

    /// Editor ID of the quest that owns `topic`, or nil when the topic names
    /// no quest or the owning plugin is not loaded.
    public func questEditorID(ofTopic topic: DialogueTopic) -> String? {
        guard
            let owner = topic.owningQuest,
            let key = ReferenceKey.resolve(owner, using: dialogue.resolver),
            case let .plugin(name, _) = key,
            let store = questStores[name]
        else {
            return nil
        }
        return store.quest(key: key)?.editorID
    }

    /// Every recorded line one INFO holds for one voice type, in response
    /// order. Empty when the INFO belongs to no loaded topic.
    public func lines(info: TopicInfo, voiceType: String) -> [VoiceLine] {
        guard let topic = dialogue.topic(ofInfo: info.formID) else { return [] }
        let quest = questEditorID(ofTopic: topic)
        let objectID = VoiceFilePath.exportedFormID(
            info.formID, masterCount: dialogue.resolver.masters.count
        )
        return info.responses.map { response in
            VoiceLine(
                path: VoiceFilePath.path(
                    plugin: pluginName,
                    voiceType: voiceType,
                    name: VoiceFilePath.Name(
                        quest: quest,
                        topic: topic.editorID,
                        objectID: objectID,
                        responseNumber: Int(response.number)
                    )
                )
            )
        }
    }

    /// The name half of every line one INFO holds, without a voice-type
    /// directory, each paired with the two editor IDs it was built from. This
    /// is what a name-derivation sweep compares against the archive listing,
    /// because the archive holds one copy per voice type and the records do not
    /// say which voice types recorded a line.
    public func fileNames(info: TopicInfo) -> [VoiceFileNameDerivation] {
        guard let topic = dialogue.topic(ofInfo: info.formID) else { return [] }
        let quest = questEditorID(ofTopic: topic)
        let objectID = VoiceFilePath.exportedFormID(
            info.formID, masterCount: dialogue.resolver.masters.count
        )
        return info.responses.map { response in
            VoiceFileNameDerivation(
                name: VoiceFilePath.fileName(
                    VoiceFilePath.Name(
                        quest: quest,
                        topic: topic.editorID,
                        objectID: objectID,
                        responseNumber: Int(response.number)
                    )
                ),
                questEditorID: quest,
                topicEditorID: topic.editorID
            )
        }
    }
}
