public import OpenSkyConditions
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyQuestsInterface

/// What the world adapters use of `SocialEventCoordinator`.
public protocol SocialEventPort: AnyObject {
    var state: SocialState { get }
    var sentCounts: [FourCC: Int] { get }
    var approachingSpeakers: Set<ReferenceKey> { get }
    func isWatchingCombat(_ actor: ReferenceKey) -> Bool
    @discardableResult func requestConversation(
        speaker: ReferenceKey, partner: ReferenceKey, now: Double
    ) -> Bool
    func meetForScene(speaker: ReferenceKey, partner: ReferenceKey, now: Double) -> Bool
    func storyEventAnswered(_ event: StoryEventData, startedQuest: Bool)
    func noteKill(victim: ReferenceKey, killer: ReferenceKey?)
    func reset()
    func restore(_ saved: SocialState)
    func tick() -> [SocialEventCommand]
}
