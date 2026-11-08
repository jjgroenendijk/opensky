public import OpenSkyConditions
public import OpenSkyQuestsInterface

/// What the world adapters use of `StoryManagerCoordinator`.
public protocol StoryManagerPort: AnyObject {
    associatedtype SocialEventCoordinator: SocialEventPort
    @discardableResult func fire(_ event: StoryEventData) -> StoryManagerWalk?
    @discardableResult func runSessionStart(lists: [PluginQuestList]) -> SessionStartReport
    var social: SocialEventCoordinator { get }
}
