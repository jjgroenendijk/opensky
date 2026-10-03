// The shell of the story manager: owns the node index, fires events, runs the
// session-start pass, and keeps the last walk for the sidebar. The rules live
// in `StoryManagerRuntime`. See docs/engine/story-manager.md.

import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyWorldState

/// What `StoryManagerCoordinator` reads from the running session.
@MainActor
public protocol StoryManagerWorld: AnyObject {
    /// Nil without game data.
    var questRuntime: QuestRuntime? { get }
    func conditionContext() -> ConditionContext
    var conditionRegistry: ConditionFunctionRegistry { get }
    /// Starts quests with their scripts. Nil: the quest runtime starts them alone.
    var questStarter: (any QuestStarting)? { get }
}

@MainActor
public final class StoryManagerCoordinator {
    /// Nil without game data.
    public var story: StoryManagerStore?
    public private(set) var lastWalk: StoryManagerWalk?
    public private(set) var sessionStart = SessionStartReport.empty
    /// Events fired this session, by code.
    public private(set) var firedCounts: [FourCC: Int] = [:]
    public var lastOutcome: String?
    weak var world: (any StoryManagerWorld)?

    public init() {}

    public func attach(world: any StoryManagerWorld) {
        self.world = world
    }

    public var runtime: StoryManagerRuntime? {
        guard let story, let world, let quests = world.questRuntime else { return nil }
        return StoryManagerRuntime(
            store: quests.store,
            quests: quests,
            story: story,
            context: world.conditionContext(),
            registry: world.conditionRegistry,
            starter: world.questStarter
        )
    }

    /// Fires one event. Nil, with the reason in `lastOutcome`, without a runtime.
    @discardableResult
    public func fire(_ event: StoryEventData) -> StoryManagerWalk? {
        firedCounts[event.event, default: 0] += 1
        guard let runtime else {
            lastOutcome = "no story manager data loaded"
            return nil
        }
        let walk = runtime.fire(event)
        lastWalk = walk
        lastOutcome = StoryManagerCore.summary(walk)
        return walk
    }

    /// Starts every quest the plugins' `.seq` lists name that has no state yet.
    @discardableResult
    public func runSessionStart(lists: [PluginQuestList]) -> SessionStartReport {
        guard let quests = world?.questRuntime else { return sessionStart }
        sessionStart = quests.runSessionStart(lists: lists, starter: world?.questStarter)
        return sessionStart
    }
}
