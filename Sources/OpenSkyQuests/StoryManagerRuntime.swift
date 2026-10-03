// The story-manager walk: an event fires, its SMEN nodes are walked in sibling
// order, node conditions pass or fail against the event data, and quest nodes
// start quests. Rules and sources: docs/engine/story-manager.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldState

/// Starts a quest the story manager or the session start picked. The app conforms,
/// so scripts attach and fragments run; without one the quest runtime starts it alone.
@MainActor
public protocol QuestStarting: AnyObject {
    func startQuest(_ quest: FormID, event: StoryEventData?) throws
}

@MainActor
public struct StoryManagerRuntime {
    public let store: WorldStateStore
    public let quests: QuestRuntime
    public let story: StoryManagerStore
    public var context: ConditionContext
    public var registry: ConditionFunctionRegistry
    public weak var starter: (any QuestStarting)?

    public init(
        store: WorldStateStore,
        quests: QuestRuntime,
        story: StoryManagerStore,
        context: ConditionContext,
        registry: ConditionFunctionRegistry,
        starter: (any QuestStarting)? = nil
    ) {
        self.store = store
        self.quests = quests
        self.story = story
        self.context = context
        self.registry = registry
        self.starter = starter
    }

    /// What the story manager remembers about `quest`, or nil when it never started it.
    public func state(of quest: FormID) -> StoryManagerQuestState? {
        quests.quests.key(for: quest)
            .flatMap { store.component(StoryManagerQuestState.self, for: $0) }
    }

    /// Fires one event and starts the quests its tree picks.
    @discardableResult
    public func fire(_ event: StoryEventData) -> StoryManagerWalk {
        var walk = Walk(runtime: self, event: event)
        _ = story.roots(forEvent: event.event).contains { walk.visit($0.id, depth: 0) }
        return StoryManagerWalk(
            event: event,
            steps: walk.steps,
            startedQuests: walk.started,
            tally: walk.evaluator.tally
        )
    }

    /// The quest-store FormID of a quest entry, or nil outside the quest store's plugin.
    func questFormID(
        _ entry: StoryManagerNode.QuestEntry,
        in node: ResolvedRecord<StoryManagerNode>
    ) -> FormID? {
        guard
            let resolved = story.nodes.index.resolvedID(
                entry.quest,
                fromPlugin: node.sourcePlugin
            )
        else { return nil }
        return quests.quests.resolver.localFormID(of: resolved)
    }

    var now: Double {
        context.clock?.totalGameSeconds ?? 0
    }

    func isRunning(_ quest: FormID) -> Bool {
        (try? quests.state(of: quest).isRunning) ?? false
    }

    /// Starts one quest and records the start for hours until reset.
    func start(_ quest: FormID, event: StoryEventData) throws {
        if let starter {
            try starter.startQuest(quest, event: event)
        } else {
            try quests.startQuestWithStartUpStage(quest, event: event)
        }
        guard let key = quests.quests.key(for: quest) else { return }
        let previous = store.component(StoryManagerQuestState.self, for: key)
            ?? StoryManagerQuestState(lastStartSeconds: 0, startCount: 0)
        store.set(previous.started(at: now), for: key)
    }
}
