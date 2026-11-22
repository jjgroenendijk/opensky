public import OpenSkyFormatsESM
public import OpenSkyPerceptionInterface

/// What the world adapters use of `PerceptionRuntime`.
public protocol PerceptionRuntimePort: AnyObject, DetectionObserving {
    func noteAttack(by target: ReferenceKey)
    func noteSoundEvent(owner: ReferenceKey, level: Float, at position: SIMD3<Float>)
    func noteSummon(by caster: ReferenceKey, at position: SIMD3<Float>)
    func soundEvent(of owner: ReferenceKey) -> DetectionSoundEvent?
    func observersDetecting(_ target: ReferenceKey) -> [ReferenceKey]
    var settings: DetectionSettings { get }
    func state(observer: ReferenceKey, target: ReferenceKey) -> DetectionPairState
}
