public import OpenSkyWorldInterface

/// What the world adapters use of `ActorStateGraphInputs`.
public protocol ActorStateGraphInputsPort {
    var isDrunk: Bool { get set }
    var taggedPerkState: ActorGraphState? { get }
}
