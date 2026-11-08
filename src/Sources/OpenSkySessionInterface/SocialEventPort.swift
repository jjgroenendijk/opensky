public import OpenSkyQuestsInterface

/// What the world adapters use of `SocialEventCoordinator`.
public protocol SocialEventPort: AnyObject {
    func reset()
    func tick() -> [SocialEventCommand]
}
