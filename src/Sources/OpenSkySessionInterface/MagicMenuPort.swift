/// What the world adapters use of `MagicMenuCoordinator`.
public protocol MagicMenuPort: AnyObject {
    @discardableResult func open() -> Bool
}
