public import OpenSkyBehavior
public import OpenSkyWorldInterface

/// What the world adapters use of `LocomotionBridge`.
public protocol LocomotionBridgePort: AnyObject {
    associatedtype ActorStateGraphInputs: ActorStateGraphInputsPort
    associatedtype LocomotionStatus: LocomotionStatusPort
    var actorState: ActorStateGraphInputs { get set }
    var footIk: Bool { get set }
    var graph: BehaviorGraphInstance? { get }
    var isRunAllowed: Bool { get set }
    var isSprintAllowed: Bool { get set }
    @discardableResult func drainMountEvents() -> [String]
    var pose: PlayerPoseBuffer { get }
    func raise(_ name: String)
    @discardableResult func raiseGraphEvent(named name: String) -> Bool
    var status: LocomotionStatus { get }
    func write(_ value: BehaviorVariableValue, to name: String)
}
