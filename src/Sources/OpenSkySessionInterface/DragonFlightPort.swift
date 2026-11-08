public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `DragonFlightCoordinator`.
public protocol DragonFlightPort: AnyObject {
    associatedtype DragonFlightState: DragonFlightStatePort
    var flights: [ReferenceKey: DragonFlightState] { get }
    @discardableResult func handle(_ name: String, from actor: ReferenceKey) -> Bool
    var handledEvents: Int { get }
    var landingEvents: [ReferenceKey: String] { get }
    var landingRequests: [ReferenceKey: DragonLandingRequest] { get }
    func order(_ order: DragonFlightOrder, for actor: ReferenceKey)
    var orders: [ReferenceKey: DragonFlightOrder] { get }
    func phase(of actor: ReferenceKey) -> DragonFlightPhase
    func tick(deltaTime: Float)
}
