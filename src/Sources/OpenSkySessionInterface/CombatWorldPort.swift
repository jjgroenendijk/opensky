public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyPhysics

/// What the world adapters use of `CombatWorldAdapter`.
public protocol CombatWorldPort: AnyObject {
    func actorFlies(_ actor: ReferenceKey) -> Bool
    func health(of key: ReferenceKey) -> (current: Float, maximum: Float)?
    /// The impact one IPDS plays on `material`, as Papyrus `PlayImpactEffect` asks.
    func impact(dataSet: FormID, material: FormID?) -> ResolvedMeleeImpact?
    /// The impact the IPDS with this editor ID plays on `material`.
    func impact(dataSetEditorID: String, material: FormID?) -> ResolvedMeleeImpact?
    func playImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>)
    func playImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>, gain: Float)
    func run(_ commands: [CombatCommand])
    func sweep(_ query: ShapeSweepQuery) -> ShapeSweepHit?
}
