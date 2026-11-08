/// What the world adapters use of `CraftingMenuCoordinator`.
public protocol CraftingMenuPort: AnyObject {
    @discardableResult func open() -> Bool
}
