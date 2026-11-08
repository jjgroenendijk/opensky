public import OpenSkyPlayer
public import OpenSkySessionInterface
import OpenSkyWorld

extension ActorStateGraphInputs: ActorStateGraphInputsPort {}
extension LocomotionBridge: LocomotionBridgePort {}
extension LocomotionGraphEventQueue: LocomotionGraphEventQueuePort {}
extension LocomotionStatus: LocomotionStatusPort {}
extension MountCoordinator: MountPort {}
extension PlayerBody: PlayerBodyPort {}
extension PlayerCoordinator: PlayerPort {}
extension PlayerFirstPersonRig: PlayerFirstPersonRigPort {}
extension PlayerMountDrive: PlayerMountDrivePort {}
extension RiddenDragonOrders: RiddenDragonOrdersPort {}
extension TalkTargetingSeam: TalkTargetingSeamPort {}
extension WalkController: WalkPort {}
