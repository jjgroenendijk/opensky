public import OpenSkyAudio
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface
public import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyWorldInterface

/// What the world adapters use of `EffectsCoordinator`.
public protocol EffectsPort: AnyObject {
    func resetHealthCues()
    associatedtype PlayerHealthCues: PlayerHealthCuesPort
    func applyGraphicsSettings(_ store: PlayerSettingsStore)
    @discardableResult func attach(
        _ key: ReferenceKey,
        to anchor: EffectAnchor,
        cause: VisualEffectCause,
        duration: Float?,
        facing: ReferenceKey?
    ) -> Int?
    func bloodyWeapon(of holder: ReferenceKey)
    func clearTemporaryBlood()
    var healthCues: PlayerHealthCues { get set }
    func heartbeatSound(_ heartbeat: Heartbeat) -> FormID?
    var records: EffectRecordStore { get }
    func showDefaultBlood(on actor: ReferenceKey, at position: SIMD3<Float>, melee: Bool)
    func showDismemberParticle(at position: SIMD3<Float>)
    func showImpact(
        _ impact: Impact,
        decal: ImpactDecal?,
        at position: SIMD3<Float>,
        on surface: ImpactSurface
    )
    var skinDecals: SkinDecalRuntime { get }
    @discardableResult func splatterScreen(damage: Float) -> Int
    @discardableResult func splatterScreen(count: Int) -> Int
    @discardableResult func startModifier(
        _ key: ReferenceKey,
        strength: Float,
        looping: Bool,
        fadeIn: Float,
        on imageSpace: inout ImageSpaceState
    ) -> Bool
    func stepHealthCues(
        share: Float,
        seconds: Float,
        heartbeatPlaying: Bool,
        imageSpace: inout ImageSpaceState
    ) -> HeartbeatChange?
    var visualEffects: VisualEffectRuntime { get }
    @discardableResult func detach(_ key: ReferenceKey, from anchor: EffectAnchor) -> Int
    @discardableResult func showCastingArt(
        _ art: FormID,
        fromPlugin plugin: String,
        on actor: ReferenceKey,
        shown: Bool
    ) -> Bool

    var flashLights: [FlashLight] { get }

    func addFlashLight(_ light: ReferenceKey, at position: SIMD3<Float>, duration: Float)
    func attachLasting(_ links: [SpellHitEffectLinks], to actor: ReferenceKey)
    func detachAll(from actor: ReferenceKey)
    func detonateAreaExplosions(of event: SpellHitEvent)
    func handleSpellHit(_ event: SpellHitEvent, imageSpace: inout ImageSpaceState)
    func showModel(
        _ path: String,
        at anchor: EffectAnchor,
        cause: VisualEffectCause,
        duration: Float
    )
    func showMuzzleFlash(
        model: String?,
        light: ReferenceKey?,
        at position: SIMD3<Float>,
        along direction: SIMD3<Float>,
        duration: Float
    )
    func step(_ seconds: Float, extraModels: [VisualEffectModel], renderer: Renderer) throws
    func stopModifier(_ key: ReferenceKey, fadeOut: Float, on imageSpace: inout ImageSpaceState)
}

/// The default arguments a protocol requirement cannot carry.
extension EffectsPort {
    @discardableResult public func attach(
        _ key: ReferenceKey,
        to anchor: EffectAnchor,
        cause: VisualEffectCause,
        duration: Float?
    ) -> Int? {
        attach(key, to: anchor, cause: cause, duration: duration, facing: nil)
    }

    public func showModel(_ path: String, at anchor: EffectAnchor, cause: VisualEffectCause) {
        showModel(path, at: anchor, cause: cause, duration: EffectArtTiming.instantSeconds)
    }

    @discardableResult public func startModifier(
        _ key: ReferenceKey,
        strength: Float,
        fadeIn: Float,
        on imageSpace: inout ImageSpaceState
    ) -> Bool {
        startModifier(key, strength: strength, looping: false, fadeIn: fadeIn, on: &imageSpace)
    }

    @discardableResult public func startModifier(
        _ key: ReferenceKey,
        strength: Float,
        looping: Bool,
        on imageSpace: inout ImageSpaceState
    ) -> Bool {
        startModifier(key, strength: strength, looping: looping, fadeIn: 0, on: &imageSpace)
    }

    @discardableResult public func startModifier(
        _ key: ReferenceKey,
        strength: Float,
        on imageSpace: inout ImageSpaceState
    ) -> Bool {
        startModifier(key, strength: strength, looping: false, fadeIn: 0, on: &imageSpace)
    }

    public func stopModifier(_ key: ReferenceKey, on imageSpace: inout ImageSpaceState) {
        stopModifier(key, fadeOut: 0, on: &imageSpace)
    }
}
