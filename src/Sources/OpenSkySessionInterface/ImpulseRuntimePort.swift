public import OpenSkyCombatInterface

/// What the world adapters use of `ImpulseRuntime`.
public protocol ImpulseRuntimePort: AnyObject {
    func advance(deltaTime: Float)
    var settings: ImpulseSettings { get }
    var water: WaterImpactSettings { get }

    var events: [ImpulseEvent] { get }
    var splashCount: Int { get }
}

/// The default arguments a protocol requirement cannot carry.
extension ImpulseRuntimePort {
    public func advance() {
        advance(deltaTime: 0)
    }
}
