// One event's pass over the story-manager tree. Branch and event nodes try
// their children until one consumes the event; a quest node starts one quest,
// or up to "num quests to run". Rules: docs/engine/story-manager.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

@MainActor
extension StoryManagerRuntime {
    struct Walk {
        let runtime: StoryManagerRuntime
        let event: StoryEventData
        var evaluator: ConditionEvaluator
        var steps: [StoryManagerStep] = []
        var started: [FormID] = []
        private var visited: Set<ResolvedFormID> = []

        init(runtime: StoryManagerRuntime, event: StoryEventData) {
            self.runtime = runtime
            self.event = event
            var context = runtime.context
            context.event = event
            // The story manager runs for the player's world, so Subject is the player.
            context.subject = .player
            context.target = event.actor1
            context.aliasQuest = nil
            evaluator = ConditionEvaluator(
                context: context, registry: runtime.registry, tally: ConditionTally()
            )
        }

        /// Returns true when the event is consumed and the walk stops.
        mutating func visit(_ id: ResolvedFormID, depth: Int) -> Bool {
            guard visited.insert(id).inserted, let node = runtime.story.nodes.record(id) else {
                return false
            }
            evaluator.context.aliasQuest = nil
            guard evaluator.evaluate(node.record.conditions).isTrue else {
                note(node, depth, .conditionsFailed)
                return false
            }
            note(node, depth, .entered)
            if node.record.kind == .quest {
                return startQuests(of: node, depth: depth)
            }
            let children = ordered(runtime.story.forest.children(of: id), random: node.record)
            return children.contains { visit($0, depth: depth + 1) }
        }

        private mutating func startQuests(
            of node: ResolvedRecord<StoryManagerNode>,
            depth: Int
        ) -> Bool {
            let record = node.record
            let entries = record.quests.compactMap { entry in
                runtime.questFormID(entry, in: node).map { (entry: entry, quest: $0) }
            }
            if
                let max = record.maxConcurrentQuests, max > 0,
                entries.count(where: { runtime.isRunning($0.quest) }) >= Int(max)
            {
                note(node, depth, .concurrentLimit)
                return false
            }
            let limit = record.flags.contains(.numberOfQuestsToRun)
                ? Int(record.questsToRun ?? 1) : 1
            var startedHere = 0
            for candidate in candidates(entries, record: record) {
                guard startedHere < limit else {
                    note(node, depth, .questRejected(candidate.quest, .limitReached))
                    continue
                }
                if let rejection = tryStart(candidate.quest, entry: candidate.entry) {
                    note(node, depth, .questRejected(candidate.quest, rejection))
                } else {
                    startedHere += 1
                    started.append(candidate.quest)
                    note(node, depth, .questStarted(candidate.quest))
                }
            }
            guard startedHere > 0, !record.flags.contains(.sharesEvent) else { return false }
            note(node, depth, .consumed)
            return true
        }

        /// Nil when the quest started.
        private mutating func tryStart(
            _ quest: FormID,
            entry: StoryManagerNode.QuestEntry
        ) -> StoryQuestRejection? {
            guard let record = runtime.quests.quests.quest(quest) else { return .unknownQuest }
            if runtime.isRunning(quest) {
                return .alreadyRunning
            }
            if
                let state = runtime.state(of: quest),
                !state.hasReset(after: entry.hoursUntilReset ?? 0, now: runtime.now)
            {
                return .resetPending
            }
            evaluator.context.aliasQuest = quest
            guard evaluator.evaluate(record.storyManagerConditions).isTrue else {
                return .conditionsFailed
            }
            do {
                try runtime.start(quest, event: event)
                return nil
            } catch {
                return .startFailed(String(describing: error))
            }
        }

        /// List order, rotated for a random node, then quests started least often
        /// first when the node does all before repeating.
        private mutating func candidates(
            _ entries: [(entry: StoryManagerNode.QuestEntry, quest: FormID)],
            record: StoryManagerNode
        ) -> [(entry: StoryManagerNode.QuestEntry, quest: FormID)] {
            var list = ordered(entries, random: record)
            if record.flags.contains(.doAllBeforeRepeating) {
                let counts = list.map { runtime.state(of: $0.quest)?.startCount ?? 0 }
                list = zip(list, counts).enumerated()
                    .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
                    .map(\.element.0)
            }
            return list
        }

        /// A random node takes its list from a start drawn from the condition random
        /// stream, so a seeded session repeats.
        private mutating func ordered<T>(_ items: [T], random record: StoryManagerNode) -> [T] {
            guard record.flags.contains(.random), items.count > 1 else { return items }
            let start = evaluator.context.random.percent() % items.count
            return Array(items[start...] + items[..<start])
        }

        private mutating func note(
            _ node: ResolvedRecord<StoryManagerNode>,
            _ depth: Int,
            _ outcome: StoryNodeOutcome
        ) {
            steps.append(StoryManagerStep(
                node: node.id, editorID: node.record.editorID, depth: depth, outcome: outcome
            ))
        }
    }
}
