public import OpenSkyFormatsAnimation
public import OpenSkyWorldInterface

/// What the world adapters use of `VehicleWheelRig`.
public protocol VehicleWheelRigPort {
    func pose(_ turns: VehicleWheelTurns) -> [HKABonePose]
}
