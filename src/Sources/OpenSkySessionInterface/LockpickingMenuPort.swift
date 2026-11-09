public import OpenSkyMenusInterface
public import OpenSkyWorldInterface

/// What the world adapters use of `LockpickingMenuController`.
public protocol LockpickingMenuPort: AnyObject {
    func handle(_ refusal: ActivationRefusalEvent)
    /// Steps the open board by the wall clock; the menu keeps its own while the world is paused.
    func tick()
    func route(_ event: MenuInputEvent)
}
