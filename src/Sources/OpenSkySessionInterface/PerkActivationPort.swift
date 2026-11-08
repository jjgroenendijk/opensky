public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `PerkActivationCoordinator`.
public protocol PerkActivationPort: AnyObject {
    @discardableResult func activate(_ target: InteractionTarget) -> Bool
    func promptLabel(on key: ReferenceKey) -> String?
}
