public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface
public import OpenSkyPhysics
public import OpenSkyRenderCore
public import OpenSkyScriptingInterface

/// What the world adapters use of `EffectsWorldAdapter`.
public protocol EffectsWorldPort: AnyObject, PapyrusEffectPresenting, PapyrusTrapWorldBridge {
    func detonateEffectExplosion(_ explosion: ReferenceKey, at position: SIMD3<Float>)
    var effects: any EffectsPort { get }
    func fadeOutHealthCues()
    func handleSpellHit(_ event: SpellHitEvent)
    func knockDown(_ actor: ReferenceKey, from source: SIMD3<Float>, magnitude: Float) -> Bool
    func knockDownActor(_ actor: ReferenceKey, awayFrom source: ReferenceKey, magnitude: Float)
        -> Bool
    func nextHazardKey() -> ReferenceKey
    func placeAtMe(_ base: ReferenceKey, at anchor: ReferenceKey, count: Int) -> ReferenceKey?
    func projectileAndFlashLights() -> [RenderPointLight]
    func race(of actor: ReferenceKey) -> Race?
    func renderLight(_ key: ReferenceKey, at position: SIMD3<Float>, strength: Float)
        -> RenderPointLight?
    func resetHealthCues()
    func showMuzzleFlash(
        _ visuals: ProjectileVisuals,
        at position: SIMD3<Float>,
        along direction: SIMD3<Float>
    )
    func waterPushRace(of actor: ReferenceKey) -> WaterPushRace
}
