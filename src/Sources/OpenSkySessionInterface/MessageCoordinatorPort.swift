public import OpenSkyMenusInterface
public import OpenSkyScriptingInterface

/// What the world adapters use of `MessageCoordinator`.
public protocol MessageCoordinatorPort: AnyObject, PapyrusPresenting {
    @discardableResult func postNotification(_ text: String) -> Bool
    @discardableResult func postWorldNotice(_ notice: WorldNotice) -> Bool
    func presentChoices(
        title: String?,
        text: String,
        buttons: [String],
        answer: @escaping (Int) -> Void
    )
    func noteInputEvent(_ event: String)
    var presentation: MessageBoxPresentation? { get }
    func reloadHelpRecords()
    func route(_ event: MenuInputEvent)
    func route(_ event: MenuPointerEvent)
    func tick(time: Double)
}
