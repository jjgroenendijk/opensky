public import OpenSkyPlayer
public import OpenSkyRenderCore
public import OpenSkySessionInterface
import OpenSkyWorld

extension ActorStateGraphInputs: ActorStateGraphInputsPort {}
extension LocomotionBridge: LocomotionBridgePort {}
extension LocomotionStatus: LocomotionStatusPort {}
extension MountCoordinator: MountPort {}
extension PlayerBody: PlayerBodyPort {
    public var clothAnimation: (any RenderAnimation)? {
        cloth
    }
}

extension PlayerCoordinator: PlayerPort {}
extension PlayerFirstPersonRig: PlayerFirstPersonRigPort {}
extension PlayerMountDrive: PlayerMountDrivePort {}
extension RiddenDragonOrders: RiddenDragonOrdersPort {}
extension TalkTargetingSeam: TalkTargetingSeamPort {}
extension WalkController: WalkPort {}
