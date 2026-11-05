// How far a hit knocks its target back, how hard an explosion or a projectile pushes a
// body, and how much a fast heavy body hurts. Values in, values out
// (docs/engine/impulses.md).

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyPhysics
import simd

/// What a strong hit does to its target.
nonisolated public struct HitKnock: Equatable, Sendable {
    /// Units per second along the ground, away from the attacker.
    public let speed: Float
    /// The hit passed the knockdown test. The actor is pushed the full distance.
    public let isKnockdown: Bool
}

nonisolated public enum HitKnockback {
    /// Nil for a hit below `fKnockdownCurrentHealthThreshold` percent of current health,
    /// or one that kills. `roll` is 0 to 1; below `fKnockdownChance` the hit knocks down.
    /// `scale` is 1 for a melee hit and `fProjectileKnockMultBiped` for a ranged one.
    public static func knock(
        damage: Float,
        health: (current: Float, maximum: Float),
        roll: Float,
        scale: Float = 1,
        settings: ImpulseSettings
    ) -> HitKnock? {
        guard
            damage.isFinite, damage > 0, health.current.isFinite, health.current > damage,
            scale.isFinite, scale > 0,
            damage * 100 >= health.current * settings.knockdownCurrentHealthThreshold
        else { return nil }
        let knocksDown = damage * 100 >= health.maximum * settings.knockdownBaseHealthThreshold
            || roll < settings.knockdownChance
        let longest = max(settings.knockbackForceMax, 0)
        let distance = knocksDown ? longest : min(damage * settings.knockbackDamageMult, longest)
        let speed = distance * scale / max(settings.knockbackTime, 0.01)
        guard speed.isFinite, speed > 0 else { return nil }
        return HitKnock(speed: speed, isKnockdown: knocksDown)
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

/// One push for the solver: `linear` at the centre of mass, and the turn the same
/// impulse would give at `point`, times `angularScale`.
nonisolated public struct BodyImpulse: Equatable, Sendable {
    public let key: ReferenceKey
    /// Kilogram engine units per second.
    public let linear: SIMD3<Float>
    public let point: SIMD3<Float>
    public let angularScale: Float

    public init(key: ReferenceKey, linear: SIMD3<Float>, point: SIMD3<Float>, angularScale: Float) {
        self.key = key
        self.linear = linear
        self.point = point
        self.angularScale = angularScale
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

    /// The push `blast` gives one body, strongest at its nearest side.
    public static func explosion(
        _ blast: ImpulseBlast, on body: ImpulseBody, isSource: Bool, settings: ImpulseSettings
    ) -> BodyImpulse? {
        let away = direction(from: blast.center, to: body.position)
        let near = body.position - away * body.boundingRadius
        var amount = blast.strength(at: simd_distance(blast.center, near))
            * settings.explosionLinearMult * settings.gameplayImpulse.value(for: body.kind)
            * havokScale * massScale(body.mass, minimum: settings.gameplayImpulseMinMass)
        if isSource {
            amount *= settings.explosionSourceRefMult
        }
        let lift = SIMD3<Float>(0, 0, max(settings.explosionUpBias, 0))
        let lifted = simd_normalize(away + lift)
        guard amount.isFinite, amount > 0, lifted.isFiniteVector else { return nil }
        return BodyImpulse(
            key: body.key, linear: lifted * amount, point: near,
            angularScale: max(settings.explosionAngularMult, 0)
        )
    }

    /// The speed `blast` knocks an actor `distance` away from it, in units a second.
    public static func explosionKnock(
        _ blast: ImpulseBlast, distance: Float, settings: ImpulseSettings
    ) -> Float {
        let speed = blast.strength(at: distance) * settings.explosionLinearMult
            * settings.gameplayImpulse.biped * havokScale
        return speed.isFinite ? max(speed, 0) : 0
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
