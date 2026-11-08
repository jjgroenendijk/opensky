public import OpenSkyFormatsESM
public import OpenSkyPerceptionInterface

/// What the world adapters use of `PerceptionRuntime`.
public protocol PerceptionRuntimePort: AnyObject, DetectionObserving {
    func noteAttack(by target: ReferenceKey)
    func noteDetectionEvent(owner: ReferenceKey, at position: SIMD3<Float>)
    func observersDetecting(_ target: ReferenceKey) -> [ReferenceKey]
    var settings: DetectionSettings { get }
    func state(observer: ReferenceKey, target: ReferenceKey) -> DetectionPairState
}
