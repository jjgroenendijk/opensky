// Immutable DIAL/INFO/VTYP index. Unlike flat record stores, DIAL owns a
// type-7 child group and INFO file order is selection-significant, so this
// walks the top group's direct record/group sequence.

import Foundation

nonisolated final class DialogueStore: Sendable {
    private let topicsByFormID: [UInt32: DialogueTopic]
    private let topicFormIDsByEditorID: [String: UInt32]
    private let infosByTopicFormID: [UInt32: [TopicInfo]]
    private let infosByFormID: [UInt32: TopicInfo]
    private let voicesByFormID: [UInt32: VoiceType]
    private let voiceFormIDsByEditorID: [String: UInt32]

    /// DIAL, INFO or VTYP records whose field container could not be decoded.
    let skippedRecordCount: Int

    static let empty = DialogueStore(topics: [], infosByTopic: [:], voiceTypes: [])

    convenience init(file: ESMFile, localized: Bool? = nil) {
        let isLocalized = localized ?? ((try? file.pluginHeader().isLocalized) ?? false)
        var topics: [DialogueTopic] = []
        var infosByTopic: [UInt32: [TopicInfo]] = [:]
        var voiceTypes: [VoiceType] = []
        var skipped = 0

        if let top = file.topGroup(of: "DIAL"), let children = try? top.children() {
            for child in children {
                switch child {
                case let .record(record):
                    guard record.type == "DIAL", !record.isDeleted else { continue }
                    guard let topic = try? DialogueTopic(record: record, localized: isLocalized)
                    else {
                        skipped += 1
                        continue
                    }
                    topics.append(topic)
                case let .group(group):
                    guard group.kind == .topicChildren, let parent = group.parentFormID else {
                        continue
                    }
                    let result = Self.decodeInfos(in: group, localized: isLocalized)
                    infosByTopic[parent, default: []].append(contentsOf: result.infos)
                    skipped += result.skipped
                }
            }
        }

        if let top = file.topGroup(of: "VTYP"), let children = try? top.children() {
            for case let .record(record) in children
                where record.type == "VTYP" && !record.isDeleted
            {
                guard let voice = try? VoiceType(record: record) else {
                    skipped += 1
                    continue
                }
                voiceTypes.append(voice)
            }
        }
        self.init(
            topics: topics,
            infosByTopic: infosByTopic,
            voiceTypes: voiceTypes,
            skippedRecordCount: skipped
        )
    }

    init(
        topics: [DialogueTopic],
        infosByTopic: [UInt32: [TopicInfo]],
        voiceTypes: [VoiceType],
        skippedRecordCount: Int = 0
    ) {
        var topicsByFormID: [UInt32: DialogueTopic] = [:]
        var topicIDs: [String: UInt32] = [:]
        for topic in topics {
            topicsByFormID[topic.formID.rawValue] = topic
            if let editorID = topic.editorID, !editorID.isEmpty {
                topicIDs[editorID.lowercased()] = topic.formID.rawValue
            }
        }
        var infosByFormID: [UInt32: TopicInfo] = [:]
        for infos in infosByTopic.values {
            for info in infos {
                infosByFormID[info.formID.rawValue] = info
            }
        }
        var voicesByFormID: [UInt32: VoiceType] = [:]
        var voiceIDs: [String: UInt32] = [:]
        for voice in voiceTypes {
            voicesByFormID[voice.formID.rawValue] = voice
            if let editorID = voice.editorID, !editorID.isEmpty {
                voiceIDs[editorID.lowercased()] = voice.formID.rawValue
            }
        }
        self.topicsByFormID = topicsByFormID
        topicFormIDsByEditorID = topicIDs
        infosByTopicFormID = infosByTopic
        self.infosByFormID = infosByFormID
        self.voicesByFormID = voicesByFormID
        voiceFormIDsByEditorID = voiceIDs
        self.skippedRecordCount = skippedRecordCount
    }

    var topicCount: Int {
        topicsByFormID.count
    }

    var infoCount: Int {
        infosByFormID.count
    }

    var voiceTypeCount: Int {
        voicesByFormID.count
    }

    var isEmpty: Bool {
        topicCount == 0 && infoCount == 0 && voiceTypeCount == 0
    }

    func topic(_ id: FormID) -> DialogueTopic? {
        topicsByFormID[id.rawValue]
    }

    func topic(editorID: String) -> DialogueTopic? {
        topicFormIDsByEditorID[editorID.lowercased()].flatMap { topicsByFormID[$0] }
    }

    func infos(for topic: FormID) -> [TopicInfo] {
        infosByTopicFormID[topic.rawValue] ?? []
    }

    func info(_ id: FormID) -> TopicInfo? {
        infosByFormID[id.rawValue]
    }

    func voiceType(_ id: FormID) -> VoiceType? {
        voicesByFormID[id.rawValue]
    }

    func voiceType(editorID: String) -> VoiceType? {
        voiceFormIDsByEditorID[editorID.lowercased()].flatMap { voicesByFormID[$0] }
    }

    private static func decodeInfos(
        in group: ESMGroup,
        localized: Bool
    ) -> (infos: [TopicInfo], skipped: Int) {
        guard let children = try? group.children() else { return ([], 1) }
        var infos: [TopicInfo] = []
        var skipped = 0
        for case let .record(record) in children where record.type == "INFO" && !record.isDeleted {
            guard let info = try? TopicInfo(record: record, localized: localized) else {
                skipped += 1
                continue
            }
            infos.append(info)
        }
        return (infos, skipped)
    }
}
