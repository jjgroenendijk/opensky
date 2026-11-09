public import OpenSkyWorldInterface

/// What the world adapters use of `CellAnimatedVehicle`.
public protocol CellAnimatedVehiclePort {
    associatedtype VehicleWheelRig: VehicleWheelRigPort
    var reference: UInt32 { get }

    var pose: SkinnedPoseBuffer { get }
    var rig: VehicleWheelRig { get }
}
