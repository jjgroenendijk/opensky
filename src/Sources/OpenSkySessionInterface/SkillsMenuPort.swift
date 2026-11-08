public import OpenSkyMenusInterface

/// What the world adapters use of `SkillsMenuCoordinator`.
public protocol SkillsMenuPort: AnyObject {
    func route(_ event: MenuInputEvent)
    func tick(now: Double)
    associatedtype SkillsMenuModel: SkillsMenuModelPort
    var model: SkillsMenuModel? { get }
    @discardableResult func open() -> Bool
    func setSkyEnabled(_ enabled: Bool)
    var snapshot: SkillsMenuSnapshot { get }
}
