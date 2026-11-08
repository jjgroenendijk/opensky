import Foundation
import OpenSkyGameData

/// One multiplier per kind of body.
nonisolated public struct ImpulseKindMultipliers: Equatable, Sendable {
    public var biped: Float
    public var clutter: Float
    public var prop: Float
    public var debrisLarge: Float
    public var trap: Float

    public init(biped: Float, clutter: Float, prop: Float, debrisLarge: Float, trap: Float) {
        self.biped = biped
        self.clutter = clutter
        self.prop = prop
        self.debrisLarge = debrisLarge
        self.trap = trap
    }
}

/// What a push lands on, by its collision layer.
nonisolated public enum ImpulseBodyKind: String, Equatable, Sendable, CaseIterable {
    case biped, clutter, prop, debrisLarge, trap

    /// SkyrimLayer indices, as the install's `COLL` records number them.
    public init(collisionLayer: UInt8) {
        self = switch collisionLayer {
        case 8, 32, 33: .biped
        case 10: .prop
        case 14, 16, 24: .trap
        case 20: .debrisLarge
        default: .clutter
        }
    }
}

nonisolated public struct ImpulseSettings: Equatable, Sendable {
    /// The agility the knock formulas read; the game passes this fixed value.
    public static let knockAgility: Float = 50

    /// `fKnockbackDamageMult` and `fKnockbackDamageBase`: push units per point of damage.
    public var knockbackDamageMult: Float = 5
    public var knockbackDamageBase: Float = 50
    /// `fKnockbackAgilMult` and `fKnockbackAgilBase`: the agility scale of the push.
    public var knockbackAgilityMult: Float = -0.008
    public var knockbackAgilityBase: Float = 1
    /// `fKnockbackForceMax`: the longest push, in units.
    public var knockbackForceMax: Float = 128
    /// `fKnockbackTime`: seconds the push takes.
    public var knockbackTime: Float = 0.3
    /// `fKnockdownCurrentHealthThreshold`: a hit of this percent of current health or
    /// more pushes, and rolls for a knockdown.
    public var knockdownCurrentHealthThreshold: Float = 50
    /// `fKnockdownBaseHealthThreshold`: a hit of this percent of base health knocks down.
    public var knockdownBaseHealthThreshold: Float = 75
    /// `fKnockdownChance`: the highest knockdown chance, 0 to 1.
    public var knockdownChance: Float = 0.25
    /// `fKnockdownDamageMult`, `...DamageBase`, `...AgilMult`, `...AgilBase`: the chance.
    public var knockdownDamageMult: Float = 0.3
    public var knockdownDamageBase: Float = 0
    public var knockdownAgilityMult: Float = 1
    public var knockdownAgilityBase: Float = 0
    /// `fExplosionForceKnockdownMinimum`: the falloff a blast needs to knock down.
    public var explosionKnockdownMinimum: Float = 0.15
    /// `fExplosionKnockStateExplodeDownTime`: seconds a knocked-down actor may lie.
    public var knockdownTime: Float = 15
    /// `fGameplayImpulseScale`: an explosion's force to a body impulse.
    public var gameplayImpulseScale: Float = 150
    /// `fExplosionMaxImpulse`: the largest impulse one blast gives a body.
    public var explosionMaxImpulse: Float = 8000
    /// `fExplosionForceMultLinear` and `...Angular`.
    public var explosionLinearMult: Float = 1
    public var explosionAngularMult: Float = 1
    /// `fExplosionSourceRefMult`: the object a projectile struck takes this much more.
    public var explosionSourceRefMult: Float = 3
    /// `fExplosionForceClutterUpBias`: the upward part added to a blast's direction.
    public var explosionUpBias: Float = 0.5
    /// `fGameplayImpulseMult*`: an explosion's push by the kind of body.
    public var gameplayImpulse = ImpulseKindMultipliers(
        biped: 0.04, clutter: 1, prop: 0.1, debrisLarge: 1, trap: 0.15
    )
    /// `fGameplayImpulseMinMass`: a lighter body moves as if it weighed this.
    public var gameplayImpulseMinMass: Float = 5
    /// `fProjectileKnockMult*`: a projectile's push by the kind of body.
    public var projectileKnock = ImpulseKindMultipliers(
        biped: 0.25, clutter: 0.15, prop: 1, debrisLarge: 0.15, trap: 0.05
    )
    /// `fProjectileKnockMinMass`.
    public var projectileKnockMinMass: Float = 5
    /// `fPhysicsDamage1Mass` to `3`, and their damage: the heaviest tier a body reaches.
    public var physicsDamageTiers: [PhysicsDamageTier] = [
        PhysicsDamageTier(mass: 20, damage: 1),
        PhysicsDamageTier(mass: 50, damage: 5),
        PhysicsDamageTier(mass: 100, damage: 10)
    ]
    /// `fPhysicsDamageSpeedMin`: slower bodies do not hurt, units per second.
    public var physicsDamageSpeedMin: Float = 500
    /// `fPhysicsDamageSpeedBase` and `...Mult`: damage scales by `base + mult * speed`.
    public var physicsDamageSpeedBase: Float = 1
    public var physicsDamageSpeedMult: Float = 0.0001

    public static let vanilla = Self()

    public init() {}
}

/// One `fPhysicsDamage<n>` pair: a body of `mass` kilograms or more deals `damage`.
nonisolated public struct PhysicsDamageTier: Equatable, Sendable {
    public var mass: Float
    public var damage: Float

    public init(mass: Float, damage: Float) {
        self.mass = mass
        self.damage = damage
    }
}
