// The shell of the story manager: owns the node index, fires events, runs the
// session-start pass, and keeps the last walk for state reads. The rules live
// in `StoryManagerRuntime`. See docs/engine/story-manager.md.

public import OpenSkyConditions
public import OpenSkyFormatsCore
public import OpenSkyGameData
public import OpenSkyQuestsInterface
import OpenSkyWorldState

/// What `StoryManagerCoordinator` reads from the running session.
@MainActor
public protocol StoryManagerWorld: AnyObject {
    /// Nil without game data.
    var questRuntime: QuestRuntime? { get }
    func conditionContext() -> ConditionContext
    /// Starts quests with their scripts. Nil: the quest runtime starts them alone.
    var questStarter: (any QuestStarting)? { get }
}

@MainActor
public final class StoryManagerCoordinator {
    /// Nil without game data.
    public let story: StoryManagerStore?
    public private(set) var sessionStart = SessionStartReport.empty
    /// Events fired this session, by code.
    public private(set) var firedCounts: [FourCC: Int] = [:]
    /// The newest events, oldest first, for the `state story` read.
    public private(set) var recentEvents: [StoryEventData] = []
    static let recentEventLimit = 16
    /// The newest quests a walk tried and did not start, oldest first.
    public private(set) var recentRejections: [StoryRejectedQuest] = []
    /// NPC conversations, hellos, and found bodies, which fire through this coordinator.
    public let social: SocialEventCoordinator
    let world: any StoryManagerWorld

    public init(
        world: any StoryManagerWorld, social: SocialEventCoordinator, story: StoryManagerStore?
    ) {
        self.world = world
        self.social = social
        self.story = story
    }

    public var runtime: StoryManagerRuntime? {
        guard let story, let quests = world.questRuntime else { return nil }
        return StoryManagerRuntime(
            store: quests.store,
            quests: quests,
            story: story,
            context: world.conditionContext(),
            starter: world.questStarter
        )
    }

    /// Fires one event. Nil without a runtime, and for `QSTR`, whose quest starts with
    /// no walk of the event nodes.
    @discardableResult
    public func fire(_ event: StoryEventData) -> StoryManagerWalk? {
        firedCounts[event.event, default: 0] += 1
        recentEvents.append(event)
        if recentEvents.count > Self.recentEventLimit {
            recentEvents.removeFirst(recentEvents.count - Self.recentEventLimit)
        }
        guard event.event != "QSTR", let walk = runtime?.fire(event) else { return nil }
        for step in walk.steps {
            guard case let .questRejected(quest, reason) = step.outcome else { continue }
            recentRejections.append(StoryRejectedQuest(
                event: event.event,
                quest: quest,
                reason: reason
            ))
        }
        if recentRejections.count > Self.recentEventLimit {
            recentRejections.removeFirst(recentRejections.count - Self.recentEventLimit)
        }
        return walk
    }

    /// Starts every quest the plugins' `.seq` lists name that has no state yet.
    @discardableResult
    public func runSessionStart(lists: [PluginQuestList]) -> SessionStartReport {
        guard let quests = world.questRuntime else { return sessionStart }
        sessionStart = quests.runSessionStart(lists: lists, starter: world.questStarter)
        return sessionStart
    }
}
