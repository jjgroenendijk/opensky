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

    /// Editor ID of the quest that owns `topic`, or nil when the topic names
    /// no quest or the owning plugin is not loaded.
    public func questEditorID(ofTopic topic: DialogueTopic) -> String? {
        guard
            let owner = topic.owningQuest,
            let key = ReferenceKey.resolve(owner, using: dialogue.resolver),
            case let .plugin(name, _) = key,
            let quest = questStores[name]?.quest(key: key)
            ?? questStores.values.lazy.compactMap({ $0.quest(key: key) }).first
        else {
            return nil
        }
        return quest.editorID
    }

    /// The file-name FormID of an INFO: as its own plugin writes it, the plugin's
    /// own index cleared. A load-order store holds a renumbered ID.
    private func exportedFormID(of id: FormID, writtenBy source: FormIDResolver) -> UInt32 {
        let local = dialogue.resolver.resolve(id).flatMap { source.localFormID(of: $0) } ?? id
        return VoiceFilePath.exportedFormID(local, masterCount: source.masters.count)
    }

    /// Every recorded line one INFO says for one voice type, in response order.
    /// A shared INFO (`DNAM`) says the lines recorded for its target. Empty when
    /// the INFO belongs to no loaded topic.
    public func lines(info: TopicInfo, voiceType: String) -> [VoiceLine] {
        let info = dialogue.responseSource(ofInfo: info.formID) ?? info
        guard let topic = dialogue.topic(ofInfo: info.formID) else { return [] }
        let quest = questEditorID(ofTopic: topic)
        let source = dialogue.sourceResolver(ofInfo: info.formID)
        let objectID = exportedFormID(of: info.formID, writtenBy: source)
        return info.responses.map { response in
            VoiceLine(
                path: VoiceFilePath.path(
                    plugin: source.pluginName,
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
        let source = dialogue.sourceResolver(ofInfo: info.formID)
        let objectID = exportedFormID(of: info.formID, writtenBy: source)
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
