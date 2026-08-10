// Turns a dialogue response plus a speaker's voice type into the archive path
// of its recording. The naming rule itself lives in `VoiceFilePath`; this type
// supplies the four strings that rule needs by walking the records: the
// defining plugin, the INFO's owning topic, that topic's owning quest, and the
// response numbers the INFO carries.
//
// Quest lookup goes through `ReferenceKey` rather than a raw FormID because a
// topic in one plugin may be owned by a quest defined in one of its masters.
// A session that loaded only that master's plugin still resolves; a session
// that loaded neither gets no quest name, which is a wrong path rather than a
// crash — `DialogueVoice` reports the miss instead of playing silence.
//
// Documented in docs/formats/fuz.md and docs/engine/audio.md.

import Foundation

/// One recorded response of one INFO.
nonisolated struct VoiceLine: Equatable {
    /// TRDT response number, one-based; the trailing `_1`, `_2` of the name.
    let responseNumber: Int
    /// Canonical VFS key of the `.fuz` file.
    let path: String
}

/// One derived voice file name beside the editor IDs it came from. The pair is
/// what makes a name-derivation sweep's mismatch report actionable: a name that
/// does not match tells you nothing on its own about which half of the rule is
/// wrong.
nonisolated struct VoiceFileNameDerivation: Equatable {
    let name: String
    let questEditorID: String?
    let topicEditorID: String?
}

nonisolated struct VoiceLineLocator {
    let dialogue: DialogueStore
    /// Lowercased plugin file name -> that plugin's QUST index. A topic's
    /// owning quest is looked up here by session-stable key.
    private let questStores: [String: QuestStore]

    init(dialogue: DialogueStore, quests: QuestStore?) {
        self.init(
            dialogue: dialogue,
            questStores: quests.map { [$0.resolver.pluginName.lowercased(): $0] } ?? [:]
        )
    }

    init(dialogue: DialogueStore, questStores: [String: QuestStore]) {
        self.dialogue = dialogue
        self.questStores = questStores
    }

    /// File name of the plugin whose records these are, which is also the
    /// directory name under `sound\voice\`.
    var pluginName: String {
        dialogue.resolver.pluginName
    }

    /// Editor ID of the quest that owns `topic`, or nil when the topic names
    /// no quest or the owning plugin is not loaded.
    func questEditorID(ofTopic topic: DialogueTopic) -> String? {
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
    func lines(info: TopicInfo, voiceType: String) -> [VoiceLine] {
        guard let topic = dialogue.topic(ofInfo: info.formID) else { return [] }
        let quest = questEditorID(ofTopic: topic)
        let objectID = VoiceFilePath.exportedFormID(
            info.formID, masterCount: dialogue.resolver.masters.count
        )
        return info.responses.map { response in
            VoiceLine(
                responseNumber: Int(response.number),
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
    func fileNames(info: TopicInfo) -> [VoiceFileNameDerivation] {
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
