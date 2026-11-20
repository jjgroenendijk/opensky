public import OpenSkyConditions
public import OpenSkyFormatsCore
public import OpenSkyQuestsInterface

/// What the world adapters use of `StoryManagerCoordinator`.
public protocol StoryManagerPort: AnyObject {
    associatedtype SocialEventCoordinator: SocialEventPort
    @discardableResult func fire(_ event: StoryEventData) -> StoryManagerWalk?
    var firedCounts: [FourCC: Int] { get }
    var recentEvents: [StoryEventData] { get }
    var recentRejections: [StoryRejectedQuest] { get }
    @discardableResult func runSessionStart(lists: [PluginQuestList]) -> SessionStartReport
    var social: SocialEventCoordinator { get }
}
