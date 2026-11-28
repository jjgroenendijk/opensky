// The values an explosion carries and the world seam it acts through. The
// runtime decides; the session applies damage, plays sounds, starts the
// image-space modifier, and places hazards. See docs/formats/explosions.md.

public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyPhysics
import simd

/// Everything an explosion needs from the session around it.
@MainActor
public protocol ExplosionWorld: AnyObject {
    /// Actors a blast can reach, with their feet positions.
    func explosionTargets() -> [MeleeTarget]
    /// Where the camera is, which sets the image-space strength.
    func explosionViewer() -> SIMD3<Float>?
    @discardableResult
    func applyExplosionDamage(_ amount: Float, to target: ReferenceKey) -> Bool
    func playExplosionSound(_ sound: ReferenceKey, at position: SIMD3<Float>)
    func startExplosionImageSpace(_ modifier: ReferenceKey, strength: Float)
    /// Places a hazard. Returns false when the session cannot.
    @discardableResult
    func placeExplosionHazard(_ hazard: ReferenceKey, at position: SIMD3<Float>) -> Bool
    /// Shows the explosion's own model briefly at the blast.
    func showExplosionModel(_ path: String, at position: SIMD3<Float>)
    /// Lights the blast briefly with a `LIGH`.
    func showExplosionLight(_ light: ReferenceKey, at position: SIMD3<Float>)
    /// Plays an `IPDS` on the surface under the blast.
    func playExplosionImpact(_ dataSet: ReferenceKey, at position: SIMD3<Float>)
    /// How far along the line from `start` to `end` the first wall is, or nil when clear.
    func explosionObstruction(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Float?
    /// The resident destructible objects within `radius` of `center`, by their origin.
    func explosionObjects(within radius: Float, of center: SIMD3<Float>) -> [MeleeTarget]
    /// Deals `amount` destruction damage to `object`. False when it is not destructible.
    @discardableResult
    func applyDestructionDamage(_ amount: Float, to object: ReferenceKey) -> Bool
    /// Puts the new reference in the world. False when it cannot.
    @discardableResult
    func placeExplosionObject(_ placement: ExplosionObjectPlacement) -> Bool
    /// `owner` made a detection sound event of the `EXPL` sound level at `position`.
    func noteExplosionSound(owner: ReferenceKey, level: UInt32?, at position: SIMD3<Float>)
    /// Casts the `EXPL` enchantment from `shooter` on `targets`; a hostile one skips the
    /// shooter. Returns the actors it reached.
    @discardableResult
    func castExplosionEnchantment(
        _ enchantment: ReferenceKey, from shooter: ReferenceKey?, on targets: [ReferenceKey]
    ) -> [ReferenceKey]
}

extension ExplosionWorld {
    public func showExplosionLight(_: ReferenceKey, at _: SIMD3<Float>) {}
    public func playExplosionImpact(_: ReferenceKey, at _: SIMD3<Float>) {}

    public func explosionObstruction(from _: SIMD3<Float>, to _: SIMD3<Float>) -> Float? {
        nil
    }

    public func explosionObjects(within _: Float, of _: SIMD3<Float>) -> [MeleeTarget] {
        []
    }

    public func applyDestructionDamage(_: Float, to _: ReferenceKey) -> Bool {
        false
    }

    public func placeExplosionObject(_: ExplosionObjectPlacement) -> Bool {
        false
    }

    public func noteExplosionSound(owner _: ReferenceKey, level _: UInt32?, at _: SIMD3<Float>) {}

    public func castExplosionEnchantment(
        _: ReferenceKey, from _: ReferenceKey?, on _: [ReferenceKey]
    ) -> [ReferenceKey] {
        []
    }
}
