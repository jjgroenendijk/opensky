// Immutable DIAL/INFO/VTYP index. DIAL owns a type-7 child group and INFO order
// matters, so this walks the top group's sequence. Each INFO also resolves to a
// session-stable `ReferenceKey`, which said-state is keyed by.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public final class DialogueStore: Sendable {
    private let topicsByFormID: [UInt32: DialogueTopic]
    private let topicFormIDsByEditorID: [String: UInt32]
    private let infosByTopicFormID: [UInt32: [TopicInfo]]
    private let infosByFormID: [UInt32: TopicInfo]
    private let topicFormIDsByInfoFormID: [UInt32: UInt32]
    private let voicesByFormID: [UInt32: VoiceType]
    private let voiceFormIDsByEditorID: [String: UInt32]
    /// Raw INFO FormID -> session-stable identity, resolved once through the
    /// plugin's master list so said-state and saves never key off a
    /// load-order-relative number.
    private let keysByInfoFormID: [UInt32: ReferenceKey]
    private let branchIndex: DialogueBranchIndex
    /// Master-list resolver of the plugin these records came from, retained so
    /// a caller can resolve the FormIDs the records *point at*.
    public let resolver: FormIDResolver

    /// DIAL, INFO or VTYP records that failed to decode.
    public let skippedRecords: SkippedRecords

    public var skippedRecordCount: Int {
        skippedRecords.total
    }

    public static let empty = DialogueStore(
        topics: [],
        infosByTopic: [:],
        voiceTypes: [],
        resolver: FormIDResolver(pluginName: "", masters: [])
    )

    /// - Parameter pluginName: file name of `file`, needed because a plugin
    ///   does not record its own name and `ReferenceKey` is built from it.
    public convenience init(file: ESMFile, pluginName: String, localized: Bool? = nil) {
        let isLocalized = localized ?? file.isLocalized
        var topics: [DialogueTopic] = []
        var infosByTopic: [UInt32: [TopicInfo]] = [:]
        var voiceTypes: [VoiceType] = []
        var skipped = SkippedRecords()
        let masters = skipped.masters(of: file)

        if let top = file.topGroup(of: "DIAL") {
            for child in skipped.children(of: top) {
                switch child {
                case let .record(record):
                    guard record.type == "DIAL", !record.isDeleted else { continue }
                    let topic = skipped.decode(record) {
                        try DialogueTopic(record: $0, localized: isLocalized)
                    }
                    topics.append(contentsOf: topic.map { [$0] } ?? [])
                case let .group(group):
                    guard group.kind == .topicChildren, let parent = group.parentFormID else {
                        continue
                    }
                    let infos = Self.decodeInfos(
                        in: group,
                        localized: isLocalized,
                        skipped: &skipped
                    )
                    infosByTopic[parent, default: []].append(contentsOf: infos)
                }
            }
        }

        let branches = DialogueBranchIndex.decode(file: file, skipped: &skipped)
        if let top = file.topGroup(of: "VTYP") {
            for case let .record(record) in skipped.children(of: top)
                where record.type == "VTYP" && !record.isDeleted
            {
                let voice = skipped.decode(record) { try VoiceType(record: $0) }
                voiceTypes.append(contentsOf: voice.map { [$0] } ?? [])
            }
        }
        self.init(
            topics: topics,
            infosByTopic: infosByTopic,
            voiceTypes: voiceTypes,
            resolver: FormIDResolver(pluginName: pluginName, masters: masters),
            skippedRecords: skipped,
            branches: branches.branches,
            views: branches.views
        )
    }

    public init(
        topics: [DialogueTopic],
        infosByTopic: [UInt32: [TopicInfo]],
        voiceTypes: [VoiceType],
        resolver: FormIDResolver,
        skippedRecords: SkippedRecords = SkippedRecords(),
        branches: [DialogueBranch] = [],
        views: [DialogueView] = []
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
        var owningTopics: [UInt32: UInt32] = [:]
        var infoKeys: [UInt32: ReferenceKey] = [:]
        for (topicFormID, infos) in infosByTopic {
            for info in infos {
                infosByFormID[info.formID.rawValue] = info
                owningTopics[info.formID.rawValue] = topicFormID
                if let key = ReferenceKey.resolve(info.formID, using: resolver) {
                    infoKeys[info.formID.rawValue] = key
                }
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
        topicFormIDsByInfoFormID = owningTopics
        self.voicesByFormID = voicesByFormID
        voiceFormIDsByEditorID = voiceIDs
        keysByInfoFormID = infoKeys
        branchIndex = DialogueBranchIndex(branches: branches, views: views, topics: topics)
        self.resolver = resolver
        self.skippedRecords = skippedRecords
    }

    public var topicCount: Int {
        topicsByFormID.count
    }

    public var infoCount: Int {
        infosByFormID.count
    }

    public var voiceTypeCount: Int {
        voicesByFormID.count
    }

    public var isEmpty: Bool {
        topicCount == 0 && infoCount == 0 && voiceTypeCount == 0
    }

    public func topic(_ id: FormID) -> DialogueTopic? {
        topicsByFormID[id.rawValue]
    }

    public func topic(editorID: String) -> DialogueTopic? {
        topicFormIDsByEditorID[editorID.lowercased()].flatMap { topicsByFormID[$0] }
    }

    public func infos(for topic: FormID) -> [TopicInfo] {
        infosByTopicFormID[topic.rawValue] ?? []
    }

    public func info(_ id: FormID) -> TopicInfo? {
        infosByFormID[id.rawValue]
    }

    /// The DIAL record whose child group holds `id`, or nil when no loaded
    /// plugin declares that INFO.
    public func topic(ofInfo id: FormID) -> DialogueTopic? {
        topicFormIDsByInfoFormID[id.rawValue].flatMap { topicsByFormID[$0] }
    }

    /// Session-stable key for one INFO, which is how said-state and the save
    /// file address it. Nil for a FormID this plugin does not define.
    public func key(forInfo id: FormID) -> ReferenceKey? {
        keysByInfoFormID[id.rawValue]
    }

    /// Topics in FormID order, which is the deterministic order selection
    /// walks them in when two topics share a priority.
    public func sortedTopics() -> [DialogueTopic] {
        topicsByFormID.keys.sorted().compactMap { topicsByFormID[$0] }
    }

    public func branch(_ id: FormID) -> DialogueBranch? {
        branchIndex.branchesByFormID[id.rawValue]
    }

    /// DLBR records of one quest, in file order.
    public func branches(forQuest quest: FormID) -> [DialogueBranch] {
        branchIndex.branchIDsByQuest[quest.rawValue, default: []]
            .compactMap { branchIndex.branchesByFormID[$0] }
    }

    /// The DLBR a topic's BNAM names.
    public func branch(ofTopic topic: FormID) -> DialogueBranch? {
        self.topic(topic)?.owningBranch.flatMap { branch($0) }
    }

    /// The DIAL records whose BNAM names this branch, in file order.
    public func topics(inBranch branch: FormID) -> [DialogueTopic] {
        branchIndex.topicIDsByBranch[branch.rawValue, default: []]
            .compactMap { topicsByFormID[$0] }
    }

    /// DLBR records with the blocking flag, in FormID order.
    public func blockingBranches() -> [DialogueBranch] {
        branchIndex.blockingBranches
    }

    public func views(forQuest quest: FormID) -> [DialogueView] {
        branchIndex.viewsByQuest[quest.rawValue] ?? []
    }

    public var branchCount: Int {
        branchIndex.branchesByFormID.count
    }

    /// DLBR records in FormID order.
    public func sortedBranches() -> [DialogueBranch] {
        branchIndex.branchesByFormID.keys.sorted().compactMap { branchIndex.branchesByFormID[$0] }
    }

    public func voiceType(editorID: String) -> VoiceType? {
        voiceFormIDsByEditorID[editorID.lowercased()].flatMap { voicesByFormID[$0] }
    }

    private static func decodeInfos(
        in group: ESMGroup,
        localized: Bool,
        skipped: inout SkippedRecords
    ) -> [TopicInfo] {
        let children: [ESMGroup.Child]
        do {
            children = try group.children()
        } catch {
            skipped.note("INFO", error: error)
            return []
        }
        var infos: [TopicInfo] = []
        for case let .record(record) in children where record.type == "INFO" && !record.isDeleted {
            let info = skipped.decode(record) { try TopicInfo(record: $0, localized: localized) }
            infos.append(contentsOf: info.map { [$0] } ?? [])
        }
        return infos
    }
}
