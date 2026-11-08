public import OpenSkyFormatsESM
public import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What the world adapters use of `VehicleCoordinator`.
public protocol VehiclePort: AnyObject {
    associatedtype VehicleCore: VehicleCorePort
    var core: VehicleCore { get }
    @discardableResult func board(_ rider: ReferenceKey, on vehicle: ReferenceKey) -> Bool
    var lastPoses: [ReferenceKey: ReferenceTransformOverride] { get }
    var playersLastMount: ReferenceKey? { get }
    @discardableResult func seat(_ rider: ReferenceKey, on horse: ReferenceKey, bone: String)
        -> Bool

    func advance() -> [VehicleCommand]
    func animationEvent(_ name: String, from actor: ReferenceKey) -> [VehicleCommand]
    func detach(_ follower: ReferenceKey, standing: Bool) -> [VehicleCommand]
    func setVehicle(_ rider: ReferenceKey, vehicle: ReferenceKey?) -> [VehicleCommand]
    func tow(_ cart: ReferenceKey, by horse: ReferenceKey) -> [VehicleCommand]
}

/// The default arguments a protocol requirement cannot carry.
extension VehiclePort {
    @discardableResult public func detach(_ follower: ReferenceKey) -> [VehicleCommand] {
        detach(follower, standing: false)
    }
}
