// The game's grab: what the player may hold, how strong the hold spring is, where it pulls,
// and when it lets go. See docs/engine/grab.md.

import OpenSkyFormatsMesh
public import OpenSkyGameData
import simd

nonisolated public struct GrabSettings: Equatable, Sendable {
    /// `fZKeyMaxForce`: the spring's largest pull for a full-strength grab, in m/s² per unit
    /// of the object's mass.
    public var maxForce: Float = 100
    /// `fZKeyMaxForceWeightHigh`: the actor mass at which a body is held at the least force.
    public var weightHigh: Float = 150
    /// The heaviest root body, in physics mass, that may be grabbed.
    public var maximumMass: Float = 100
    /// How long Activate must be held before a grab starts, in seconds.
    public var holdDelay: Float = 0.2
    public var damping: Float = 0.5
    public var elasticity: Float = 0.2
    public var objectDamping: Float = 0.75
    /// The spring breaks when its target is this far from the held point.
    public var breakDistance: Float = 96
    /// Past this distance, a much heavier body touching the object breaks the hold.
    public var contactDistance: Float = 10
    public var contactMassRatio: Float = 4
    /// The hold distance is at least the player's collision radius plus this.
    public var holdMargin: Float = 5
    /// A held item heavier than this stops the player from running.
    public var noRunItemWeight: Float = 75

    public static let vanilla = Self()

    public init() {}

    /// Only the two force settings are in `Skyrim.esm`; the rest are the program's own.
    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fZKeyMaxForce", into: &settings, \.maxForce)
        store.read("fZKeyMaxForceWeightHigh", into: &settings, \.weightHigh)
        return settings
    }
}

/// What is held: a loose object, or an actor's ragdoll.
nonisolated public enum GrabTarget: Equatable, Sendable {
    /// `trap` is an object on collision layer 14, TRAP.
    case object(trap: Bool)
    /// `totalMass` sums every body; `jointed` is true when the grabbed body has a joint
    /// other than contacts.
    case actor(totalMass: Float, jointed: Bool)
}

/// The spring's force scale `s` and elasticity scale `e`.
nonisolated public struct GrabStrength: Equatable, Sendable {
    public let force: Float
    public let elasticity: Float

    public init(force: Float, elasticity: Float) {
        self.force = force
        self.elasticity = elasticity
    }

    /// A body of total mass 90 with a joint gives force 0.2 + 0.8 × 60 / 150 = 0.52.
    public static func of(_ target: GrabTarget, settings: GrabSettings = .vanilla) -> Self {
        switch target {
        case let .object(trap):
            return trap ? Self(force: 0.5, elasticity: 0.1) : Self(force: 1, elasticity: 1)
        case let .actor(totalMass, jointed):
            let high = max(settings.weightHigh, 1)
            let mass = min(max(totalMass.isFinite ? totalMass : high, 0), high)
            let force = 0.2 + 0.8 * (high - mass) / high
            return jointed
                ? Self(force: force, elasticity: 1)
                : Self(force: force * 0.2, elasticity: 0.1)
        }
    }
}

/// One grab: where the spring pulls and how it moves the held body.
nonisolated public struct GrabHold: Equatable, Sendable {
    public let strength: GrabStrength
    /// From the eye to the grabbed point, fixed when the grab starts.
    public let distance: Float
    public let settings: GrabSettings

    public init(
        strength: GrabStrength, grabDistance: Float, playerRadius: Float,
        settings: GrabSettings = .vanilla
    ) {
        self.strength = strength
        distance = max(grabDistance, playerRadius + settings.holdMargin)
        self.settings = settings
    }

    /// The point ahead of the eye at the hold distance; `blocked` is the distance to the
    /// first hit on the way, which shortens it for this frame.
    public func target(
        eye: SIMD3<Float>,
        look: SIMD3<Float>,
        blocked: Float? = nil
    ) -> SIMD3<Float> {
        let length = simd_length(look)
        guard length > 0, length.isFinite else { return eye }
        let reach = min(distance, blocked ?? distance)
        return eye + look / length * max(reach, 0)
    }

    /// The held body's velocity after one step of the spring. The pull is the elasticity
    /// share of the gap per step, less the damped velocity, capped by the force scale.
    public func velocity(
        position: SIMD3<Float>, velocity: SIMD3<Float>, target: SIMD3<Float>, dt: Float
    ) -> SIMD3<Float> {
        guard dt > 0, dt.isFinite else { return velocity }
        let elasticity = settings.elasticity * strength.elasticity
        var change = (target - position) * (elasticity / dt) - velocity * settings.damping
        let limit = settings.maxForce * strength.force * Self.unitsPerMetre * dt
        let size = simd_length(change)
        if size > limit, size > 0 {
            change *= limit / size
        }
        return (velocity + change) * max(0, 1 - settings.objectDamping * dt)
    }

    /// Whether the game lets go this step: the target is too far from the held point, or,
    /// past a short distance, a touching body is much heavier than the held one.
    public func letsGo(
        target: SIMD3<Float>, held: SIMD3<Float>, objectMass: Float, heaviestContact: Float?
    ) -> Bool {
        let gap = simd_distance(target, held)
        if gap > settings.breakDistance {
            return true
        }
        guard gap > settings.contactDistance, let heaviestContact else { return false }
        return heaviestContact > settings.contactMassRatio * objectMass
    }

    static let unitsPerMetre = NIFCollisionModel.havokToEngineScale
}

/// What `state grab` shows.
nonisolated public struct PlayerGrabReadout: Equatable, Sendable {
    public var isEnabled: Bool
    /// `idle`, `waiting`, or `holding`.
    public var phase: String
    /// The held reference's FormID, and the ragdoll body it holds by for an actor.
    public var held: UInt32?
    public var body: Int?
    public var distance: Float?
    public var strength: GrabStrength?
    /// Why the last hold ended.
    public var lastLetGo: String?

    public init(
        isEnabled: Bool, phase: String, held: UInt32? = nil, body: Int? = nil,
        distance: Float? = nil, strength: GrabStrength? = nil, lastLetGo: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.phase = phase
        self.held = held
        self.body = body
        self.distance = distance
        self.strength = strength
        self.lastLetGo = lastLetGo
    }
}
