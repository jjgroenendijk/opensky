public import OpenSkyConditions
public import OpenSkyWorldInterface

/// What the world adapters use of `ActorGraphWorldAdapter`.
public protocol ActorGraphWorldPort: AnyObject {
    func drive(_ update: NPCLocomotionDriveUpdate)
    func graphVariableResolution() -> GraphVariableResolution
    var graphs: any ActorGraphPort { get }
}
