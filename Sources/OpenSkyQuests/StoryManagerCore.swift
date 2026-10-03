// The readout text of the story manager. Values in, values out.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

public enum StoryManagerCore {
    public static func summary(_ walk: StoryManagerWalk) -> String {
        let started = walk.startedQuests.count
        return "\(walk.event.event): \(walk.steps.count) nodes, \(started) quests started"
    }

    /// One line per step, indented by depth.
    public static func lines(
        _ walk: StoryManagerWalk,
        questName: (FormID) -> String
    ) -> [String] {
        walk.steps.map { step in
            let indent = String(repeating: "  ", count: step.depth)
            let name = step.editorID ?? step.node.description
            return "\(indent)\(name): \(text(step.outcome, questName: questName))"
        }
    }

    public static func text(_ outcome: StoryNodeOutcome, questName: (FormID) -> String) -> String {
        switch outcome {
        case .conditionsFailed: "conditions failed"
        case .entered: "entered"
        case let .questStarted(quest): "started \(questName(quest))"
        case let .questRejected(quest, reason): "\(questName(quest)) not started, \(text(reason))"
        case .concurrentLimit: "max concurrent quests running"
        case .consumed: "event consumed"
        }
    }

    public static func text(_ rejection: StoryQuestRejection) -> String {
        switch rejection {
        case .unknownQuest: "unknown quest"
        case .alreadyRunning: "already running"
        case .resetPending: "hours until reset not passed"
        case .conditionsFailed: "quest conditions failed"
        case let .startFailed(reason): "start failed: \(reason)"
        case .limitReached: "node limit reached"
        }
    }

    public static func text(_ report: SessionStartReport) -> String {
        let listed = report.entries.count
        return "\(report.startedCount) of \(listed) started, "
            + "\(report.missingLists.count) plugins without a list, "
            + "\(report.brokenLists.count) broken"
    }

    /// The event's subtree, one line per node, indented by depth.
    public static func tree(
        _ store: StoryManagerStore,
        event: FourCC,
        questName: (ResolvedRecord<StoryManagerNode>, StoryManagerNode.QuestEntry) -> String
    ) -> [String] {
        var lines: [String] = []
        var pending = store.roots(forEvent: event).reversed().map { ($0.id, 0) }
        while let (id, depth) = pending.popLast() {
            guard let node = store.nodes.record(id) else { continue }
            let indent = String(repeating: "  ", count: depth)
            var line = "\(indent)\(node.record.editorID ?? id.description)"
            if node.record.kind == .quest {
                line += ": " + node.record.quests.map { questName(node, $0) }
                    .joined(separator: ", ")
            }
            lines.append(line)
            pending += store.forest.children(of: id).reversed().map { ($0, depth + 1) }
        }
        return lines
    }
}
