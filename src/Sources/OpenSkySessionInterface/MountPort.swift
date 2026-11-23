public import OpenSkyFormatsESM
public import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorldInterface

/// What the world adapters use of `MountCoordinator`.
public protocol MountPort: AnyObject {
    associatedtype RiddenDragonOrders: RiddenDragonOrdersPort
    associatedtype PlayerMountDrive: PlayerMountDrivePort
    var dragonOrders: RiddenDragonOrders { get }
    var lockIsToggle: Bool { get }
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
    @discardableResult func mount(_ key: ReferenceKey) -> [MountCommand]
    var ridesStolenMount: Bool { get }
    var settings: MountSettings { get }
}

extension MountPort {
    public func allowRiddenHorseSprint(_ allowed: Bool) {
        drive?.bridge.isSprintAllowed = allowed
    }
}
