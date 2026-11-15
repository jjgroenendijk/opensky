public import OpenSkyMenusInterface

/// What the world adapters use of `TweenMenuCoordinator`.
public protocol TweenMenuPort: AnyObject {
    var isOpen: Bool { get }
    var highlighted: TweenMenuChoice? { get }
    var showsLevelUp: Bool { get }
    var isClosing: Bool { get }
    var lastResult: String { get }
    @discardableResult func open(onChoose: @escaping (TweenMenuChoice) -> Void) -> Bool
}
