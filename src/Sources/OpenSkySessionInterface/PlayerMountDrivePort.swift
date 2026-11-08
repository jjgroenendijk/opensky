public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `PlayerMountDrive`.
public protocol PlayerMountDrivePort: AnyObject {
    associatedtype DragonFlightState: DragonFlightStatePort
    associatedtype LocomotionBridge: LocomotionBridgePort
    var bridge: LocomotionBridge { get }
    var flight: DragonFlightState? { get }
    var heading: Float { get }
    var kind: MountKind { get }
    var motion: MountMotion { get }
    var mount: ReferenceKey { get }
    var turnRamp: MountTurnRamp { get }
}
