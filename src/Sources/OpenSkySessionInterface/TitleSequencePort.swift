/// What the world adapters use of `TitleSequenceCoordinator`.
public protocol TitleSequencePort: AnyObject {
    var isLoaded: Bool { get }
    var isShown: Bool { get }
    var lastSequence: String? { get }
    func show(_ shown: Bool)
    @discardableResult func start(_ sequence: String) -> Bool
    func tick()
}
