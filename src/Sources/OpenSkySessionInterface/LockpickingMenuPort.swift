public import Foundation
public import OpenSkyMenusInterface
public import OpenSkyWorldInterface

/// What the world adapters use of `LockpickingMenuController`.
public protocol LockpickingMenuPort: AnyObject {
    func handle(_ refusal: ActivationRefusalEvent)
    func tick(now: Date)
    func route(_ event: MenuInputEvent)
}
