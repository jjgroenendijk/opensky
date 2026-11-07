// How far a hit knocks its target back, how hard an explosion or a projectile pushes a
// body, and how much a fast heavy body hurts. Values in, values out
// (docs/engine/impulses.md).

import Foundation
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyPhysics
import simd

/// What a melee hit does to its target.
nonisolated public struct HitKnock: Equatable, Sendable {
    /// Units per second along the ground, away from the attacker.
    public let speed: Float
    /// The hit passed the knockdown test, so the target falls.
    public let isKnockdown: Bool
}

nonisolated public enum HitKnockback {
    /// The push of a melee hit that lands and does not kill; nil otherwise. `roll` is
    /// 0 to 1 for the knockdown test.
    public static func knock(
        damage: Float, health: (current: Float, maximum: Float), roll: Float,
        settings: ImpulseSettings
    ) -> HitKnock? {
        guard
            damage.isFinite, damage >= 0, health.current.isFinite, health.current > damage
        else { return nil }
        let speed = distance(damage: damage, settings: settings) / max(settings.knockbackTime, 0.01)
        guard speed.isFinite, speed > 0 else { return nil }
        let down = knocksDown(damage: damage, health: health, roll: roll, settings: settings)
        return HitKnock(speed: speed, isKnockdown: down)
    }

    /// Units a hit of `damage` slides its target:
    /// `(damage * mult + base) * (agilityMult * 50 + agilityBase)`, at most the maximum.
    public static func distance(damage: Float, settings: ImpulseSettings) -> Float {
        let agility = settings.knockbackAgilityMult * ImpulseSettings.knockAgility
            + settings.knockbackAgilityBase
        let force = (damage * settings.knockbackDamageMult + settings.knockbackDamageBase) * agility
        return simd_clamp(force, 0, max(settings.knockbackForceMax, 0))
    }

    /// A hit over `fKnockdownBaseHealthThreshold` percent of base health knocks down. One
    /// over `fKnockdownCurrentHealthThreshold` percent of current health rolls, per mille.
    public static func knocksDown(
        damage: Float, health: (current: Float, maximum: Float), roll: Float,
        settings: ImpulseSettings
    ) -> Bool {
        guard health.current > 0, health.maximum > 0, damage < health.current else {
            return false
        }
        if damage * 100 / health.maximum > settings.knockdownBaseHealthThreshold {
            return true
        }
        guard damage * 100 / health.current > settings.knockdownCurrentHealthThreshold else {
            return false
        }
        let agility = settings.knockdownAgilityMult * ImpulseSettings.knockAgility
            + settings.knockdownAgilityBase
        guard agility > 0 else { return false }
        let chance = min(
            (damage * settings.knockdownDamageMult + settings.knockdownDamageBase) / agility,
            settings.knockdownChance
        )
        return Int(roll * 1000) < Int(chance * 1000)
    }
}

/// A loose body a push can reach.
nonisolated public struct ImpulseBody: Equatable, Sendable {
    public let key: ReferenceKey
    public let reference: FormID
    /// Centre of mass, world space.
    public let position: SIMD3<Float>
    public let velocity: SIMD3<Float>
    /// Kilograms.
    public let mass: Float
    public let boundingRadius: Float
    public let kind: ImpulseBodyKind
    /// The `MATT` of the body's first collision shape.
    public let material: FormID?
    /// The `MATT` of the surface the body last touched. Nil when unknown.
    public var surfaceMaterial: FormID?

    public init(
        key: ReferenceKey, reference: FormID, position: SIMD3<Float>,
        velocity: SIMD3<Float> = .zero, mass: Float, boundingRadius: Float,
        kind: ImpulseBodyKind, material: FormID? = nil
    ) {
        self.material = material
        self.key = key
        self.reference = reference
        self.position = position
        self.velocity = velocity
        self.mass = mass
        self.boundingRadius = boundingRadius
        self.kind = kind
    }
}

/// One push for the solver: `linear` at the centre of mass, the turn the same impulse
/// would give at `point` times `angularScale`, and an extra `angular` impulse.
nonisolated public struct BodyImpulse: Equatable, Sendable {
    public let key: ReferenceKey
    /// Kilogram engine units per second.
    public let linear: SIMD3<Float>
    public let point: SIMD3<Float>
    public let angularScale: Float
    /// Kilogram square engine units per second.
    public let angular: SIMD3<Float>

    public init(
        key: ReferenceKey, linear: SIMD3<Float>, point: SIMD3<Float>, angularScale: Float,
        angular: SIMD3<Float> = .zero
    ) {
        self.key = key
        self.linear = linear
        self.point = point
        self.angularScale = angularScale
        self.angular = angular
    }
}

/// How an explosion knocks down the actors in it, from its `EXPL` flags.
nonisolated public enum ExplosionKnockdown: Equatable, Sendable {
    case never, always, byFormula

    /// Flag 0x4 knocks down always, 0x8 by the knockdown formula.
    public init(flags: UInt32?) {
        let flags = flags ?? 0
        self = flags & 0x4 != 0 ? .always : flags & 0x8 != 0 ? .byFormula : .never
    }
}

/// The hit the knockdown formula weighs: its damage, the target's health before it, and
/// a roll of 0 to 1.
nonisolated public struct KnockdownHit: Sendable {
    public let damage: Float
    public let health: (current: Float, maximum: Float)
    public let roll: Float

    public init(damage: Float, health: (current: Float, maximum: Float), roll: Float) {
        self.damage = damage
        self.health = health
        self.roll = roll
    }
}

/// One explosion as its push reads it: the `EXPL` force in Havok units, and the radius
/// it falls off to zero over.
nonisolated public struct ImpulseBlast: Equatable, Sendable {
    public let force: Float
    public let radius: Float
    public let center: SIMD3<Float>

    public init(force: Float, radius: Float, center: SIMD3<Float>) {
        self.force = force
        self.radius = radius
        self.center = center
    }

    func strength(at distance: Float) -> Float {
        ExplosionFalloff.damage(force, radius: radius, distance: distance)
    }
}

nonisolated public enum GameplayImpulse {
    /// Havok metres to engine units.
    public static let havokScale = NIFCollisionModel.havokToEngineScale

    /// The push `blast` gives one body in its radius: the same at any distance, scaled by
    /// the body's kind, its mass under `fGameplayImpulseMinMass`, and the impulse cap.
    /// `spin` is three values in -1...1 for the random turn.
    public static func explosion(
        _ blast: ImpulseBlast, on body: ImpulseBody, isSource: Bool, spin: SIMD3<Float>,
        settings: ImpulseSettings
    ) -> BodyImpulse? {
        guard simd_distance(blast.center, body.position) <= blast.radius else { return nil }
        var direction = direction(from: blast.center, to: body.position)
        if body.kind == .biped {
            direction.z += max(settings.explosionUpBias, 0)
            direction = simd_normalize(direction)
        }
        let force = blast.force * (isSource ? settings.explosionSourceRefMult : 1)
        var amount = force * settings.gameplayImpulseScale
            * settings.gameplayImpulse.value(for: body.kind)
        amount *= massScale(body.mass, minimum: settings.gameplayImpulseMinMass)
        amount = min(amount, max(settings.explosionMaxImpulse, 0))
        guard amount.isFinite, amount > 0, direction.isFiniteVector else { return nil }
        let turn = simd_clamp(spin, SIMD3(repeating: -1), SIMD3(repeating: 1))
        return BodyImpulse(
            key: body.key, linear: direction * amount * settings.explosionLinearMult,
            point: body.position, angularScale: 0,
            angular: turn * amount * settings.explosionAngularMult * havokScale
        )
    }

    /// Whether `blast` knocks down an actor `distance` away: it must reach past
    /// `fExplosionForceKnockdownMinimum` of its falloff, and pass its knockdown mode.
    public static func explosionKnocksDown(
        _ blast: ImpulseBlast, mode: ExplosionKnockdown, distance: Float, hit: KnockdownHit,
        settings: ImpulseSettings
    ) -> Bool {
        guard
            ExplosionFalloff.fraction(radius: blast.radius, distance: distance)
            > settings.explosionKnockdownMinimum
        else { return false }
        switch mode {
        case .never: return false
        case .always: return true
        case .byFormula:
            return HitKnockback.knocksDown(
                damage: hit.damage, health: hit.health, roll: hit.roll, settings: settings
            )
        }
    }

    /// The push a projectile's `PROJ` impact force gives the body it struck, along its flight.
    public static func projectile(
        impactForce: Float, flight: SIMD3<Float>, at point: SIMD3<Float>, body: ImpulseBody,
        settings: ImpulseSettings
    ) -> BodyImpulse? {
        let amount = impactForce * settings.projectileKnock.value(for: body.kind) * havokScale
            * massScale(body.mass, minimum: settings.projectileKnockMinMass)
        guard amount.isFinite, amount > 0, simd_length(flight) > 0 else { return nil }
        return BodyImpulse(
            key: body.key, linear: simd_normalize(flight) * amount, point: point, angularScale: 1
        )
    }

    /// A body lighter than `minimum` takes the velocity change a body of `minimum` would.
    static func massScale(_ mass: Float, minimum: Float) -> Float {
        guard mass.isFinite, mass > 0, minimum.isFinite, minimum > mass else { return 1 }
        return mass / minimum
    }

    private static func direction(from start: SIMD3<Float>, to end: SIMD3<Float>) -> SIMD3<Float> {
        let offset = end - start
        let length = simd_length(offset)
        return length > 0.001 ? offset / length : SIMD3(0, 0, 1)
    }
}

nonisolated public enum PhysicsDamage {
    /// The health a body of `mass` kilograms takes off an actor it strikes at `speed`
    /// units per second. Zero below `fPhysicsDamageSpeedMin` or the lightest tier.
    public static func damage(mass: Float, speed: Float, settings: ImpulseSettings) -> Float {
        guard
            mass.isFinite, speed.isFinite, speed >= settings.physicsDamageSpeedMin,
            let tier = settings.physicsDamageTiers.filter({ mass >= $0.mass })
                .max(by: { $0.mass < $1.mass })
        else { return 0 }
        let damage = tier.damage
            * (settings.physicsDamageSpeedBase + settings.physicsDamageSpeedMult * speed)
        return damage.isFinite ? max(damage, 0) : 0
    }
}
