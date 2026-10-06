// The dialogue store over a whole load order. Every record is renumbered into the
// load-order space of `FormIDResolver.loadOrder`, as `QuestStore` does. A DLC adds
// INFOs to a vanilla topic, so the INFOs of one topic merge across plugins.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// One plugin's DIAL, INFO, DLBR, DLVW and VTYP records, in its own FormID space.
nonisolated struct PluginDialogue {
    var topics: [DialogueTopic] = []
    var infosByTopic: [UInt32: [TopicInfo]] = [:]
    var voiceTypes: [VoiceType] = []
    var branches: [DialogueBranch] = []
    var views: [DialogueView] = []
    var masters: [String] = []

    init(file: ESMFile, localized: Bool?, skipped: inout SkippedRecords) {
        let isLocalized = localized ?? file.isLocalized
        masters = skipped.masters(of: file)
        if let top = file.topGroup(of: "DIAL") {
            for child in skipped.children(of: top) {
                decode(child, localized: isLocalized, skipped: &skipped)
            }
        }
        (branches, views) = DialogueBranchIndex.decode(file: file, skipped: &skipped)
        if let top = file.topGroup(of: "VTYP") {
            for case let .record(record) in skipped.children(of: top)
                where record.type == "VTYP" && !record.isDeleted
            {
                let voice = skipped.decode(record) { try VoiceType(record: $0) }
                voiceTypes.append(contentsOf: voice.map { [$0] } ?? [])
            }
        }
    }

    private mutating func decode(
        _ child: ESMGroup.Child,
        localized: Bool,
        skipped: inout SkippedRecords
    ) {
        switch child {
        case let .record(record):
            guard record.type == "DIAL", !record.isDeleted else { return }
            let topic = skipped.decode(record) {
                try DialogueTopic(record: $0, localized: localized)
            }
            topics.append(contentsOf: topic.map { [$0] } ?? [])
        case let .group(group):
            guard group.kind == .topicChildren, let parent = group.parentFormID else { return }
            let infos = Self.decodeInfos(in: group, localized: localized, skipped: &skipped)
            infosByTopic[parent, default: []].append(contentsOf: infos)
        }
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

/// Load-order records merged by FormID: a later plugin's record wins, and a new
/// INFO joins the end of its topic.
nonisolated private struct LoadOrderDialogue {
    var topics: [UInt32: DialogueTopic] = [:]
    var infosByTopic: [UInt32: [TopicInfo]] = [:]
    var infoPositions: [UInt32: (topic: UInt32, index: Int)] = [:]
    var infoSources: [UInt32: FormIDResolver] = [:]
    var voiceTypes: [UInt32: VoiceType] = [:]
    var branches: [UInt32: DialogueBranch] = [:]
    var views: [UInt32: DialogueView] = [:]

    mutating func add(
        _ plugin: PluginDialogue,
        from source: FormIDResolver,
        into space: FormIDResolver
    ) {
        let translate = FormIDTranslation(source: source, target: space)
        for topic in plugin.topics.map({ $0.renumbered { translate($0) } }) {
            topics[topic.formID.rawValue] = topic
        }
        for (parent, infos) in plugin.infosByTopic {
            let topic = translate(FormID(parent)).rawValue
            for info in infos.map({ $0.renumbered { translate($0) } }) {
                add(info, to: topic)
                infoSources[info.formID.rawValue] = source
            }
        }
        for voice in plugin.voiceTypes.map({ $0.renumbered { translate($0) } }) {
            voiceTypes[voice.formID.rawValue] = voice
        }
        for branch in plugin.branches.map({ $0.renumbered { translate($0) } }) {
            branches[branch.formID.rawValue] = branch
        }
        for view in plugin.views.map({ $0.renumbered { translate($0) } }) {
            views[view.formID.rawValue] = view
        }
    }

    private mutating func add(_ info: TopicInfo, to topic: UInt32) {
        let id = info.formID.rawValue
        if let position = infoPositions[id] {
            infosByTopic[position.topic]?[position.index] = info
            return
        }
        infoPositions[id] = (topic, infosByTopic[topic, default: []].count)
        infosByTopic[topic, default: []].append(info)
    }
}

nonisolated extension DialogueStore {
    /// Every active plugin's dialogue records, lowest priority first.
    public convenience init(plugins: [(name: String, file: ESMFile)], localized: Bool? = nil) {
        let space = FormIDResolver.loadOrder(plugins.map(\.name))
        var merged = LoadOrderDialogue()
        var skipped = SkippedRecords()
        for plugin in plugins {
            let decoded = PluginDialogue(file: plugin.file, localized: localized, skipped: &skipped)
            let source = FormIDResolver(pluginName: plugin.name, masters: decoded.masters)
            merged.add(decoded, from: source, into: space)
        }
        self.init(
            topics: merged.topics.keys.sorted().compactMap { merged.topics[$0] },
            infosByTopic: merged.infosByTopic,
            voiceTypes: merged.voiceTypes.keys.sorted().compactMap { merged.voiceTypes[$0] },
            resolver: space,
            skippedRecords: skipped,
            branches: merged.branches.keys.sorted().compactMap { merged.branches[$0] },
            views: merged.views.keys.sorted().compactMap { merged.views[$0] },
            infoSources: merged.infoSources
        )
    }
}
