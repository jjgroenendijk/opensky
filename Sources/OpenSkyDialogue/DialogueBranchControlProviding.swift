// The Dialogue Branches section's seam: how branching scoped the open
// conversation's topics, the speaker's exclusive branch, and a branch browser.
// See docs/engine/dialogue.md.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct DialogueBranchSnapshot: Equatable, Sendable {
    public static let rowLimit = 12
    public static let empty = DialogueBranchSnapshot(
        branchCount: 0, blockingCount: 0, offeredCount: 0, notEntryCount: 0,
        blockedCount: 0, blockingBranch: nil, exclusiveBranch: nil
    )

    public let branchCount: Int
    public let blockingCount: Int
    /// Topics the last selection offered.
    public let offeredCount: Int
    /// Topics kept out because they do not start a top-level branch.
    public let notEntryCount: Int
    /// Topics kept out because a blocking branch answered.
    public let blockedCount: Int
    public let blockingBranch: String?
    /// The exclusive branch the held speaker is in.
    public let exclusiveBranch: String?

    public init(
        branchCount: Int,
        blockingCount: Int,
        offeredCount: Int,
        notEntryCount: Int,
        blockedCount: Int,
        blockingBranch: String?,
        exclusiveBranch: String?
    ) {
        self.branchCount = branchCount
        self.blockingCount = blockingCount
        self.offeredCount = offeredCount
        self.notEntryCount = notEntryCount
        self.blockedCount = blockedCount
        self.blockingBranch = blockingBranch
        self.exclusiveBranch = exclusiveBranch
    }
}

@MainActor
public protocol DialogueBranchControlProviding: AnyObject {
    var dialogueBranchSnapshot: DialogueBranchSnapshot { get }
    /// Branches whose editor ID contains `filter`, one line each.
    func branchRows(matching filter: String) -> [String]
}

extension DialogueCoordinator: DialogueBranchControlProviding {
    public var dialogueBranchSnapshot: DialogueBranchSnapshot {
        guard let index else { return .empty }
        var notEntry = 0
        var blocked = 0
        var blocking: FormID?
        for offer in selection.rejected {
            switch offer.considered.first?.rejection {
            case .notBranchEntry: notEntry += 1
            case let .blockedByBranch(branch):
                blocked += 1
                blocking = branch
            default: break
            }
        }
        let exclusive = heldSpeaker.flatMap { runtime?.exclusiveBranch(of: $0) }
        return DialogueBranchSnapshot(
            branchCount: index.branchCount,
            blockingCount: index.blockingBranches().count,
            offeredCount: selection.offers.count,
            notEntryCount: notEntry,
            blockedCount: blocked,
            blockingBranch: blocking.map { branchName($0, in: index) },
            exclusiveBranch: exclusive.map { branchName($0, in: index) }
        )
    }

    public func branchRows(matching filter: String) -> [String] {
        guard let index else { return [] }
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return index.sortedBranches().lazy
            .filter { needle.isEmpty || ($0.editorID ?? "").lowercased().contains(needle) }
            .prefix(DialogueBranchSnapshot.rowLimit)
            .map { DialogueBranchText.row($0, in: index) }
    }

    private func branchName(_ id: FormID, in index: DialogueStore) -> String {
        index.branch(id)?.editorID ?? id.description
    }
}

public enum DialogueBranchText {
    /// `Name: top-level, blocking; starts Topic; 3 topics`.
    public static func row(_ branch: DialogueBranch, in index: DialogueStore) -> String {
        var flags: [String] = []
        if branch.flags.contains(.topLevel) {
            flags.append("top-level")
        }
        if branch.flags.contains(.blocking) {
            flags.append("blocking")
        }
        if branch.flags.contains(.exclusive) {
            flags.append("exclusive")
        }
        let start = branch.startingTopic.map { id in
            index.topic(id)?.editorID ?? id.description
        } ?? "none"
        let topics = index.topics(inBranch: branch.formID).count
        let kind = flags.isEmpty ? "normal" : flags.joined(separator: ", ")
        return "\(branch.editorID ?? branch.formID.description): \(kind); "
            + "starts \(start); \(topics) topics"
    }
}

/// Lets the app's provider object stand in for its `DialogueCoordinator`.
public protocol DialogueBranchControlForwarding: DialogueBranchControlProviding {
    var dialogue: DialogueCoordinator { get }
}

extension DialogueBranchControlForwarding {
    public var dialogueBranchSnapshot: DialogueBranchSnapshot {
        dialogue.dialogueBranchSnapshot
    }

    public func branchRows(matching filter: String) -> [String] {
        dialogue.branchRows(matching: filter)
    }
}
