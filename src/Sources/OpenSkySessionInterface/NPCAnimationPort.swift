public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `NPCAnimationCoordinator`.
public protocol NPCAnimationPort: AnyObject {
    func dismount(_ rider: ReferenceKey)
    func ride(_ rider: ReferenceKey, on horse: ReferenceKey)
    func drive(_ update: NPCLocomotionDriveUpdate)
}
