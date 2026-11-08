public import OpenSkyFormatsESM
public import OpenSkyMenusInterface

/// What the world adapters use of `GiftMenuCoordinator`.
public protocol GiftMenuPort: AnyObject {
    @discardableResult func open(actor: ReferenceKey, request: GiftMenuRequest) -> Bool
}
