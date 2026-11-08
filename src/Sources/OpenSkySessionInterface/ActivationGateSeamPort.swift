public import OpenSkyGameData
public import OpenSkyWorldInterface

/// What the world adapters use of `ActivationGateSeam`.
public protocol ActivationGateSeamPort: AnyObject {
    var perkChoices: ((InteractionTarget) -> Bool)? { get set }
    var refusals: FrameSchedule<ActivationRefusalStep, ActivationRefusalEvent> { get }
    func register(
        _ step: ActivationGateStep,
        _ check: @escaping (InteractionTarget) -> ActivationRefusal?
    )
}
