// The Story Manager section's seam: the event tree, firing an event, the walk
// trace, and the session-start pass. See docs/engine/story-manager.md.

import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct StoryEventRow: Equatable, Sendable {
    public let code: String
    public let eventNodeCount: Int
    public let firedCount: Int

    public init(code: String, eventNodeCount: Int, firedCount: Int) {
        self.code = code
        self.eventNodeCount = eventNodeCount
        self.firedCount = firedCount
    }
}

nonisolated public struct StoryManagerSnapshot: Equatable, Sendable {
    public static let rowLimit = 16
    public static let empty = StoryManagerSnapshot(
        nodeCount: 0, events: [], walkLines: [], droppedWalkLines: 0,
        sessionStart: "not run", lastOutcome: nil
    )

    public let nodeCount: Int
    public let events: [StoryEventRow]
    public let walkLines: [String]
    public let droppedWalkLines: Int
    public let sessionStart: String
    public let lastOutcome: String?

    public init(
        nodeCount: Int,
        events: [StoryEventRow],
        walkLines: [String],
        droppedWalkLines: Int,
        sessionStart: String,
        lastOutcome: String?
    ) {
        self.nodeCount = nodeCount
        self.events = events
        self.walkLines = walkLines
        self.droppedWalkLines = droppedWalkLines
        self.sessionStart = sessionStart
        self.lastOutcome = lastOutcome
    }
}

@MainActor
public protocol StoryManagerControlProviding: AnyObject {
    var storyManagerSnapshot: StoryManagerSnapshot { get }
    /// The event's node tree, at most `StoryManagerSnapshot.rowLimit` lines.
    func storyTree(event code: String) -> [String]
    /// Fires `code` with the player as actor 1.
    func fireStoryEvent(code: String, keyword: FormID?, value1: Float)
}

extension StoryManagerCoordinator: StoryManagerControlProviding {
    public var storyManagerSnapshot: StoryManagerSnapshot {
        guard let story else { return .empty }
        let limit = StoryManagerSnapshot.rowLimit
        let lines = lastWalk.map { StoryManagerCore.lines($0, questName: questName) } ?? []
        return StoryManagerSnapshot(
            nodeCount: story.nodes.records.count,
            events: story.events.map { event in
                StoryEventRow(
                    code: event.description,
                    eventNodeCount: story.roots(forEvent: event).count,
                    firedCount: firedCounts[event] ?? 0
                )
            },
            walkLines: Array(lines.prefix(limit)),
            droppedWalkLines: max(0, lines.count - limit),
            sessionStart: sessionStart.entries.isEmpty && sessionStart.missingLists.isEmpty
                ? "not run" : StoryManagerCore.text(sessionStart),
            lastOutcome: lastOutcome
        )
    }

    public func storyTree(event code: String) -> [String] {
        guard let story, let event = story.events.first(where: { $0.description == code }) else {
            return []
        }
        let lines = StoryManagerCore.tree(story, event: event) { node, entry in
            runtime?.questFormID(entry, in: node).map(questName) ?? entry.quest.description
        }
        return Array(lines.prefix(StoryManagerSnapshot.rowLimit))
    }

    public func fireStoryEvent(code: String, keyword: FormID?, value1: Float) {
        guard let event = story?.events.first(where: { $0.description == code }) else {
            lastOutcome = "no event nodes for \(code)"
            return
        }
        var data = StoryEventData(event: event)
        data.actor1 = .player
        data.keyword = keyword
        data.value1 = value1
        fire(data)
    }

    func questName(_ quest: FormID) -> String {
        world?.questRuntime?.quests.quest(quest)?.editorID ?? quest.description
    }
}

/// Lets the app's provider object stand in for its `StoryManagerCoordinator`.
public protocol StoryManagerControlForwarding: StoryManagerControlProviding {
    var storyManager: StoryManagerCoordinator { get }
}

extension StoryManagerControlForwarding {
    public var storyManagerSnapshot: StoryManagerSnapshot {
        storyManager.storyManagerSnapshot
    }

    public func storyTree(event code: String) -> [String] {
        storyManager.storyTree(event: code)
    }

    public func fireStoryEvent(code: String, keyword: FormID?, value1: Float) {
        storyManager.fireStoryEvent(code: code, keyword: keyword, value1: value1)
    }
}
