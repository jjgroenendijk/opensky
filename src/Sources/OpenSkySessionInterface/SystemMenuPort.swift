public import OpenSkyMenusInterface

/// What the world adapters use of `SystemMenuCoordinator`.
public protocol SystemMenuPort: AnyObject {
    func tick(now: Double)
    associatedtype SystemMenuModel: SystemMenuModelPort
    var isOpen: Bool { get }
    var model: SystemMenuModel { get }
    var movieDiagnostics: SystemMenuMovieDiagnostics? { get }
    var movieMainPage: SystemMenuPageSnapshot? { get }
    func open()
    func quicksave()
    func route(_ event: MenuInputEvent)
    var snapshot: SystemMenuControlSnapshot { get }
    var topicPage: SystemMenuTopicPageModel? { get }
}
