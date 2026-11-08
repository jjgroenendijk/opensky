public import OpenSkyFormatsESM
public import OpenSkyRendering
public import OpenSkyWorldInterface

/// What the world adapters use of `MountCoordinator`.
public protocol MountPort: AnyObject {
    associatedtype RiddenDragonOrders: RiddenDragonOrdersPort
    associatedtype PlayerMountDrive: PlayerMountDrivePort
    var dragonOrders: RiddenDragonOrders { get }
    var drive: PlayerMountDrive? { get }
    var isActive: Bool { get }
    var lastMount: ReferenceKey? { get }
    func orderDragon(_ order: DragonFlightOrder) -> [MountCommand]
    var phase: MountPhase { get }
    func switchDragonTarget(forward: Bool) -> Bool
    func advance(
        input: CameraInput,
        cameraYaw: Float,
        weaponDrawn: Bool,
        world stepWorld: MountStepWorld
    ) -> [MountCommand]
    func dismount() -> [MountCommand]
    func handleRiderEvents(_ names: [String]) -> [MountCommand]
    func mount(_ key: ReferenceKey, stealConfirmed: Bool) -> [MountCommand]
    var settings: MountSettings { get }
}

/// The default arguments a protocol requirement cannot carry.
extension MountPort {
    @discardableResult public func mount(_ key: ReferenceKey) -> [MountCommand] {
        mount(key, stealConfirmed: false)
    }
}
