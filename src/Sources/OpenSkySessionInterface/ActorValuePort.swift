/// What the world adapters use of `ActorValueCoordinator`.
public protocol ActorValuePort: AnyObject {
    associatedtype ActorValueRuntime: ActorValueRuntimePort
    func advance(delta: Float)
    var runtime: ActorValueRuntime? { get }
}
