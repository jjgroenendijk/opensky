// The values an explosion carries and the world seam it acts through. The
// runtime decides; the session applies damage, plays sounds, starts the
// image-space modifier, and places hazards. See docs/formats/explosions.md.

import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

/// What set an explosion off, for the readout.
nonisolated public enum ExplosionCause: String, Equatable, Sendable {
    case projectile, spell, script, debug
}

/// What an explosion leaves behind through its placed-object link.
nonisolated public enum ExplosionPlacement: Equatable, Sendable {
    case hazard(ReferenceKey)
    case debris(ReferenceKey)
    /// Any other base form. Logged and skipped.
    case other(ReferenceKey, type: String)
}

/// One `EXPL` resolved against the load order.
nonisolated public struct ExplosionSpec: Equatable, Sendable {
    public let name: String
    public let damage: Float
    public let radius: Float
    public let force: Float
    public let imageSpaceRadius: Float
    public let sounds: [ReferenceKey]
    public let imageSpaceModifier: ReferenceKey?
    public let placement: ExplosionPlacement?
    public let model: String?

    public init(
        name: String,
        damage: Float = 0,
        radius: Float = 0,
        force: Float = 0,
        imageSpaceRadius: Float = 0,
        sounds: [ReferenceKey] = [],
        imageSpaceModifier: ReferenceKey? = nil,
        placement: ExplosionPlacement? = nil,
        model: String? = nil
    ) {
        self.name = name
        self.damage = damage
        self.radius = radius
        self.force = force
        self.imageSpaceRadius = imageSpaceRadius
        self.sounds = sounds
        self.imageSpaceModifier = imageSpaceModifier
        self.placement = placement
        self.model = model
    }
}

/// One detonation, kept for the readout.
nonisolated public struct ExplosionReport: Equatable, Sendable {
    public let name: String
    public let cause: ExplosionCause
    public let position: SIMD3<Float>
    /// Health taken off each actor in the radius, after falloff.
    public let damaged: [ReferenceKey: Float]
    public let soundsPlayed: Int
    /// The modifier strength at the viewer, or nil when none started.
    public let imageSpaceStrength: Float?
    public let hazardPlaced: Bool
    public let debrisThrown: Int
}

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
}
