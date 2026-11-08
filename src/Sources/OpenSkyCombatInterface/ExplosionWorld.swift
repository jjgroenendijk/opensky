public import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

/// What set an explosion off, for the readout.
nonisolated public enum ExplosionCause: String, Equatable, Sendable {
    case projectile, spell, script, debug
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
    /// `DATA` light, shown at the blast for as long as the model.
    public var light: ReferenceKey?
    /// `DATA` impact data set, played on the surface under the blast.
    public var impactDataSet: ReferenceKey?
    /// Whether the blast knocks down the actors it reaches.
    public var knockdown = ExplosionKnockdown.never

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

    public init(
        name: String,
        cause: ExplosionCause,
        position: SIMD3<Float>,
        damaged: [ReferenceKey: Float],
        soundsPlayed: Int,
        imageSpaceStrength: Float?,
        hazardPlaced: Bool,
        debrisThrown: Int
    ) {
        self.name = name
        self.cause = cause
        self.position = position
        self.damaged = damaged
        self.soundsPlayed = soundsPlayed
        self.imageSpaceStrength = imageSpaceStrength
        self.hazardPlaced = hazardPlaced
        self.debrisThrown = debrisThrown
    }
}

/// What an explosion leaves behind through its placed-object link.
nonisolated public enum ExplosionPlacement: Equatable, Sendable {
    case hazard(ReferenceKey)
    case debris(ReferenceKey)
    /// Any other base form. Logged and skipped.
    case other(ReferenceKey, type: String)
}
