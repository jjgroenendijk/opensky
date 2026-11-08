import Foundation
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAudio
import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
public import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyScripting
public import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
public import OpenSkyWorldState
public import simd

extension EffectsWorldAdapter: ImpulseWorld {}
extension EffectsWorldAdapter: PapyrusTrapWorldBridge {}
extension EffectsWorldAdapter: PapyrusEffectPresenting {}

/// Witnesses that forward to the narrow parts of `EffectsWorldAdapter`.
extension EffectsWorldAdapter {
    public func impulseBodies() -> [ImpulseBody] {
        bodyImpulses.impulseBodies()
    }

    public func playCollision(_ collision: BodyCollision) {
        bodyImpulses.playCollision(collision)
    }

    public func applyBodyImpulse(_ impulse: BodyImpulse) {
        bodyImpulses.applyBodyImpulse(impulse)
    }

    public func impulseActors() -> [MeleeTarget] {
        bodyImpulses.impulseActors()
    }

    public func waterContacts(_ contacts: [WaterSample]) {
        bodyImpulses.waterContacts(contacts)
    }

    public func waterHeight(at position: SIMD2<Float>) -> Float? {
        bodyImpulses.waterHeight(at: position)
    }

    public func waterCurrent(at point: SIMD3<Float>) -> SIMD3<Float>? {
        bodyImpulses.waterCurrent(at: point)
    }

    public func isDangerousWater(at point: SIMD3<Float>) -> Bool {
        bodyImpulses.isDangerousWater(at: point)
    }

    public func raceSize(of actor: ReferenceKey) -> Int {
        bodyImpulses.raceSize(of: actor)
    }

    public func waterPushRace(of actor: ReferenceKey) -> WaterPushRace {
        bodyImpulses.waterPushRace(of: actor)
    }

    public func isPushable(_ actor: ReferenceKey) -> Bool {
        bodyImpulses.isPushable(actor)
    }

    public func race(of actor: ReferenceKey) -> Race? {
        bodyImpulses.race(of: actor)
    }

    public func actorHealth(of actor: ReferenceKey) -> (current: Float, maximum: Float)? {
        bodyImpulses.actorHealth(of: actor)
    }

    public func knockDown(
        _ actor: ReferenceKey,
        from source: SIMD3<Float>,
        magnitude: Float
    ) -> Bool {
        bodyImpulses.knockDown(actor, from: source, magnitude: magnitude)
    }

    public func knockActor(_ actor: ReferenceKey, velocity: SIMD3<Float>, knockdown: Bool) -> Bool {
        bodyImpulses.knockActor(actor, velocity: velocity, knockdown: knockdown)
    }

    public func applyPhysicsDamage(_ amount: Float, to actor: ReferenceKey) -> Bool {
        bodyImpulses.applyPhysicsDamage(amount, to: actor)
    }

    public func showSplash(_ splash: SplashEvent) {
        bodyImpulses.showSplash(splash)
    }

    public func setMotionType(
        _ motionType: ReferenceMotionType,
        of reference: ReferenceKey
    ) -> Bool {
        trapControl.setMotionType(motionType, of: reference)
    }

    public func resetReference(_ reference: ReferenceKey, to target: ReferenceKey?) -> Bool {
        trapControl.resetReference(reference, to: target)
    }

    public func fireWeapon(
        _ weapon: ReferenceKey, from source: ReferenceKey, ammunition: ReferenceKey?
    ) -> Bool {
        trapControl.fireWeapon(weapon, from: source, ammunition: ammunition)
    }

    public func placeAtMe(
        _ base: ReferenceKey,
        at anchor: ReferenceKey,
        count: Int
    ) -> ReferenceKey? {
        trapControl.placeAtMe(base, at: anchor, count: count)
    }

    public func applyImpulse(_ impulse: SIMD3<Float>, to reference: ReferenceKey) -> Bool {
        trapControl.applyImpulse(impulse, to: reference)
    }

    public func pushActor(
        _ actor: ReferenceKey, awayFrom source: ReferenceKey,
        along direction: SIMD3<Float>?, speed: Float
    ) -> Bool {
        trapControl.pushActor(actor, awayFrom: source, along: direction, speed: speed)
    }

    public func knockDownActor(
        _ actor: ReferenceKey, awayFrom source: ReferenceKey, magnitude: Float
    ) -> Bool {
        trapControl.knockDownActor(actor, awayFrom: source, magnitude: magnitude)
    }

    public func staggerActor(_ actor: ReferenceKey, magnitude: Float) -> Bool {
        trapControl.staggerActor(actor, magnitude: magnitude)
    }

    public func playEffect(
        _ effect: ReferenceKey, on target: ReferenceKey, duration: Float?, facing: ReferenceKey?
    ) -> Bool {
        trapControl.playEffect(effect, on: target, duration: duration, facing: facing)
    }

    public func stopEffect(_ effect: ReferenceKey, on target: ReferenceKey) -> Bool {
        trapControl.stopEffect(effect, on: target)
    }

    public func applyImageSpaceModifier(
        _ modifier: ReferenceKey, strength: Float, held: Bool, fadeSeconds: Float
    ) -> Bool {
        trapControl.applyImageSpaceModifier(
            modifier,
            strength: strength,
            held: held,
            fadeSeconds: fadeSeconds
        )
    }

    public func removeImageSpaceModifier(_ modifier: ReferenceKey, fadeSeconds: Float) {
        trapControl.removeImageSpaceModifier(modifier, fadeSeconds: fadeSeconds)
    }

    public func explosionTargets() -> [MeleeTarget] {
        blasts.explosionTargets()
    }

    public func explosionViewer() -> SIMD3<Float>? {
        blasts.explosionViewer()
    }

    public func applyExplosionDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        blasts.applyExplosionDamage(amount, to: target)
    }

    public func playExplosionSound(_ sound: ReferenceKey, at position: SIMD3<Float>) {
        blasts.playExplosionSound(sound, at: position)
    }

    public func startExplosionImageSpace(_ modifier: ReferenceKey, strength: Float) {
        blasts.startExplosionImageSpace(modifier, strength: strength)
    }

    public func placeExplosionHazard(_ hazard: ReferenceKey, at position: SIMD3<Float>) -> Bool {
        blasts.placeExplosionHazard(hazard, at: position)
    }

    public func showExplosionModel(_ path: String, at position: SIMD3<Float>) {
        blasts.showExplosionModel(path, at: position)
    }

    public func projectileAndFlashLights() -> [RenderPointLight] {
        blasts.projectileAndFlashLights()
    }

    public func renderLight(
        _ key: ReferenceKey, at position: SIMD3<Float>, strength: Float
    ) -> RenderPointLight? {
        blasts.renderLight(key, at: position, strength: strength)
    }

    public func showMuzzleFlash(
        _ visuals: ProjectileVisuals, at position: SIMD3<Float>, along direction: SIMD3<Float>
    ) {
        blasts.showMuzzleFlash(visuals, at: position, along: direction)
    }

    public func showExplosionLight(_ light: ReferenceKey, at position: SIMD3<Float>) {
        blasts.showExplosionLight(light, at: position)
    }

    public func playExplosionImpact(_ dataSet: ReferenceKey, at position: SIMD3<Float>) {
        blasts.playExplosionImpact(dataSet, at: position)
    }

    public var effectCamera: VisualEffectRuntime.CameraPose? {
        effectPlacement.effectCamera
    }

    public func effectTransform(of actor: ReferenceKey) -> float4x4? {
        effectPlacement.effectTransform(of: actor)
    }

    public func effectBones(of actor: ReferenceKey) -> [String: float4x4] {
        effectPlacement.effectBones(of: actor)
    }

    public func membraneTarget(of actor: ReferenceKey) -> MembraneTarget? {
        effectPlacement.membraneTarget(of: actor)
    }

    public func detonateEffectExplosion(_ explosion: ReferenceKey, at position: SIMD3<Float>) {
        effectPlacement.detonateEffectExplosion(explosion, at: position)
    }

    public func resetHealthCues() {
        effectPlacement.resetHealthCues()
    }

    public func fadeOutHealthCues() {
        effectPlacement.fadeOutHealthCues()
    }
}
