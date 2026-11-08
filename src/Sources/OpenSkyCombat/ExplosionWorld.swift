// The values an explosion carries and the world seam it acts through. The
// runtime decides; the session applies damage, plays sounds, starts the
// image-space modifier, and places hazards. See docs/formats/explosions.md.

import OpenSkyCombatInterface
public import OpenSkyFormatsESM
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
}

extension ExplosionWorld {
    public func showExplosionLight(_: ReferenceKey, at _: SIMD3<Float>) {}
    public func playExplosionImpact(_: ReferenceKey, at _: SIMD3<Float>) {}
}
