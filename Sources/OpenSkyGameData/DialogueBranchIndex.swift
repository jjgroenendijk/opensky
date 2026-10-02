// The DLBR and DLVW part of the dialogue store: branches per quest, and each
// branch's topics through the DIAL BNAM link. See docs/formats/dialogue.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated struct DialogueBranchIndex: Sendable {
    let branchesByFormID: [UInt32: DialogueBranch]
    let branchIDsByQuest: [UInt32: [UInt32]]
    let topicIDsByBranch: [UInt32: [UInt32]]
    let viewsByQuest: [UInt32: [DialogueView]]

    init(branches: [DialogueBranch], views: [DialogueView], topics: [DialogueTopic]) {
        var byFormID: [UInt32: DialogueBranch] = [:]
        var byQuest: [UInt32: [UInt32]] = [:]
        for branch in branches {
            byFormID[branch.formID.rawValue] = branch
            if let quest = branch.quest {
                byQuest[quest.rawValue, default: []].append(branch.formID.rawValue)
            }
        }
        var topicsByBranch: [UInt32: [UInt32]] = [:]
        for topic in topics {
            guard let branch = topic.owningBranch else { continue }
            topicsByBranch[branch.rawValue, default: []].append(topic.formID.rawValue)
        }
        var viewsByQuest: [UInt32: [DialogueView]] = [:]
        for view in views {
            guard let quest = view.quest else { continue }
            viewsByQuest[quest.rawValue, default: []].append(view)
        }
        branchesByFormID = byFormID
        branchIDsByQuest = byQuest
        topicIDsByBranch = topicsByBranch
        self.viewsByQuest = viewsByQuest
    }

    /// Every live DLBR and DLVW in the plugin's top groups.
    static func decode(
        file: ESMFile,
        skipped: inout SkippedRecords
    ) -> (branches: [DialogueBranch], views: [DialogueView]) {
        var branches: [DialogueBranch] = []
        var views: [DialogueView] = []
        for record in liveRecords(of: "DLBR", in: file, skipped: &skipped) {
            branches += skipped.decode(record) { try DialogueBranch(record: $0) }.map { [$0] } ?? []
        }
        for record in liveRecords(of: "DLVW", in: file, skipped: &skipped) {
            views += skipped.decode(record) { try DialogueView(record: $0) }.map { [$0] } ?? []
        }
        return (branches, views)
    }

    private static func liveRecords(
        of type: FourCC,
        in file: ESMFile,
        skipped: inout SkippedRecords
    ) -> [ESMRecord] {
        guard let top = file.topGroup(of: type) else { return [] }
        return skipped.children(of: top).compactMap {
            guard case let .record(record) = $0, record.type == type, !record.isDeleted else {
                return nil
            }
            return record
        }
    }
}
