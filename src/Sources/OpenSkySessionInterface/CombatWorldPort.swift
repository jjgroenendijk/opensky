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
    /// The actor's race `NAM4`, the material a blade strikes.
    func impactMaterial(of actor: ReferenceKey) -> FormID?
    func playImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>)
    func playImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>, gain: Float)
    func run(_ commands: [CombatCommand])
    func sweep(_ query: ShapeSweepQuery) -> ShapeSweepHit?
}

extension CombatWorldPort {
    /// How far a sphere of `radius` moves from `center` along `direction` before it meets
    /// a wall, or nil when it travels `distance` freely.
    public func freeDistance(
        of center: SIMD3<Float>, radius: Float, along direction: SIMD3<Float>, upTo distance: Float
    ) -> Float? {
        sweep(.sphere(
            center: center, radius: radius, direction: direction, maximumDistance: distance
        ))?.distance
    }
}
