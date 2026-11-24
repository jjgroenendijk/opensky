public import OpenSkyFormatsESM
public import OpenSkyGameData
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
    /// `DATA` flag `0x40`: the fixed swap modifier never plays.
    public var ignoresImageSpaceSwap = false
    /// `DATA` sound level: 0 loud, 1 normal, 2 silent, 3 very loud.
    public var soundLevel: UInt32?
    /// `DATA` flag `0x10`: the blast reaches an actor behind a wall.
    public var ignoresLineOfSight = false
    /// `DATA` vertical offset multiplier: on an actor, the blast sits this share of its
    /// height above the feet.
    public var verticalOffset: Float = 0

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

/// Who set an explosion off, and from where, for the damage rules.
nonisolated public struct ExplosionOrigin: Equatable, Sendable {
    /// Never takes the blast's damage.
    public var shooter: ReferenceKey?
    /// The shooter's skill for the weapon that fired it; nil when the source has no skill.
    public var skill: Float?
    /// The blast's direction, the impact normal; the line of sight starts along it.
    public var direction: SIMD3<Float>?
    /// The cell the placed object goes in.
    public var location: CellSceneLocation?
    /// The reference a projectile struck, which takes `fExplosionSourceRefMult` more push.
    public var struck: FormID?
    /// The reference whose owner a placed object takes, such as a destroyed barrel; nil
    /// falls back to the shooter.
    public var owner: ReferenceKey?

    public init(
        shooter: ReferenceKey? = nil,
        skill: Float? = nil,
        direction: SIMD3<Float>? = nil,
        location: CellSceneLocation? = nil,
        struck: FormID? = nil,
        owner: ReferenceKey? = nil
    ) {
        self.owner = owner
        self.struck = struck
        self.shooter = shooter
        self.skill = skill
        self.direction = direction
        self.location = location
    }
}

/// The new reference an explosion places: its base, where, in which cell, turned how,
/// and whose owner it takes.
nonisolated public struct ExplosionObjectPlacement: Equatable, Sendable {
    public var base: ReferenceKey
    public var position: SIMD3<Float>
    public var location: CellSceneLocation?
    /// Euler angles in radians, as a placement stores them.
    public var rotation: SIMD3<Float>
    public var ownerSource: ReferenceKey?

    public init(
        base: ReferenceKey, position: SIMD3<Float>, location: CellSceneLocation? = nil,
        rotation: SIMD3<Float> = .zero, ownerSource: ReferenceKey? = nil
    ) {
        self.base = base
        self.position = position
        self.location = location
        self.rotation = rotation
        self.ownerSource = ownerSource
    }

    /// The rotation that turns a placed object to face along `direction`: a heading
    /// clockwise from +Y, and a pitch that tips it up or down.
    public static func rotation(facing direction: SIMD3<Float>?) -> SIMD3<Float> {
        guard let direction, simd_length_squared(direction) > 0 else { return .zero }
        let unit = simd_normalize(direction)
        return SIMD3(-asin(max(-1, min(1, unit.z))), 0, atan2(unit.x, unit.y))
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
    /// Whether the fixed swap modifier started.
    public var swapApplied = false
    /// Actors in the radius a wall kept the blast from.
    public var shielded: [ReferenceKey] = []
    /// Destruction damage dealt to each destructible object in the radius.
    public var objectsDamaged: [ReferenceKey: Float] = [:]
    /// Whether the placed object went into the world as a new reference.
    public var objectPlaced = false

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

/// The fixed modifier a close blast swaps in, and the power above which it does.
/// See docs/engine/explosion-effects.md#the-swap-effect.
nonisolated public struct ExplosionImageSpaceSwap: Equatable, Sendable {
    /// `fExplosionImageSpaceSwapPower`.
    public var threshold: Float = 0.75
    /// The master file's swap modifier; nil plays none.
    public var modifier: ReferenceKey?
    /// The game looks the swap up by this FormID; no shipped master holds it.
    public static let modifierFormID = FormID(0x0000_0166)

    public init(threshold: Float = 0.75, modifier: ReferenceKey? = nil) {
        self.threshold = threshold
        self.modifier = modifier
    }

    /// Whether a blast with `power` at the viewer swaps the modifier in.
    public func applies(power: Float, ignored: Bool) -> Bool {
        !ignored && modifier != nil && power > threshold
    }
}

/// What an explosion leaves behind through its placed-object link.
nonisolated public enum ExplosionPlacement: Equatable, Sendable {
    case hazard(ReferenceKey)
    case debris(ReferenceKey)
    /// Any other base form. Logged and skipped.
    case other(ReferenceKey, type: String)
}
