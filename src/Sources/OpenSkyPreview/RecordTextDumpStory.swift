// Decoded views of the dialogue-branch, scene, and story-manager records. See
// docs/formats/dialogue.md, docs/formats/scenes.md, and docs/formats/story-manager.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension RecordTextDump {
    static func storySummary(_ record: ESMRecord) throws -> String? {
        switch record.type {
        case "DLBR":
            let branch = try DialogueBranch(record: record)
            return "decoded DLBR: editorID \(branch.editorID ?? "-"), quest \(text(branch.quest)), "
                + "flags \(branchFlags(branch.flags)), starting topic \(text(branch.startingTopic))"
        case "DLVW":
            let view = try DialogueView(record: record)
            return "decoded DLVW: editorID \(view.editorID ?? "-"), quest \(text(view.quest)), "
                + "branches \(view.branches.count), topics \(view.topics.count)"
        case "SCEN":
            return try sceneSummary(Scene(record: record))
        case "SMBN", "SMQN", "SMEN":
            return try storyNodeSummary(StoryManagerNode(record: record))
        default:
            return nil
        }
    }

    private static func sceneSummary(_ scene: Scene) -> String {
        let types = Dictionary(grouping: scene.actions, by: \.type)
            .sorted { $0.key < $1.key }
            .map { "\(actionName($0.key)) \($0.value.count)" }
        return "decoded SCEN: editorID \(scene.editorID ?? "-"), quest \(text(scene.quest)), "
            + "phases \(scene.phases.count), actors \(scene.actors.count), "
            + "actions [\(types.joined(separator: ", "))], flags 0x"
            + String(scene.flags.rawValue, radix: 16, uppercase: true)
    }

    private static func storyNodeSummary(_ node: StoryManagerNode) -> String {
        var line = "decoded \(nodeType(node.kind)): editorID \(node.editorID ?? "-"), "
            + "parent \(text(node.parent)), previous sibling \(text(node.previousSibling)), "
            + "conditions \(node.conditions.count), flags 0x"
            + String(node.flags.rawValue, radix: 16, uppercase: true)
        if let event = node.event {
            line += ", event \(event)"
        }
        if node.kind == .quest {
            line += ", quests [\(node.quests.map(\.quest.description).joined(separator: ", "))]"
        }
        return line
    }

    private static func nodeType(_ kind: StoryManagerNode.Kind) -> String {
        switch kind {
        case .branch: "SMBN"
        case .quest: "SMQN"
        case .event: "SMEN"
        }
    }

    /// Action types 0, 1, and 2 are dialogue, package, and timer.
    private static func actionName(_ type: UInt16) -> String {
        switch type {
        case 0: "dialogue"
        case 1: "package"
        case 2: "timer"
        default: "type \(type)"
        }
    }

    private static func branchFlags(_ flags: DialogueBranch.Flags) -> String {
        let names: [(DialogueBranch.Flags, String)] = [
            (.topLevel, "top-level"), (.blocking, "blocking"), (.exclusive, "exclusive")
        ]
        let set = names.filter { flags.contains($0.0) }.map(\.1)
        return set.isEmpty ? "none" : set.joined(separator: " ")
    }

    private static func text(_ id: FormID?) -> String {
        id?.description ?? "-"
    }
}
