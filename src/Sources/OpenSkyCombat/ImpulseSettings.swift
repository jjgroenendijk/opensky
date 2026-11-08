// The game settings that decide how hard hits, explosions, and projectiles push actors
// and loose objects, and when a falling object hurts (docs/engine/impulses.md).

import Foundation
public import OpenSkyCombatInterface
public import OpenSkyGameData

nonisolated extension ImpulseKindMultipliers {
    public func value(for kind: ImpulseBodyKind) -> Float {
        let value = switch kind {
        case .biped: biped
        case .clutter: clutter
        case .prop: prop
        case .debrisLarge: debrisLarge
        case .trap: trap
        }
        return value.isFinite ? max(value, 0) : 0
    }
}

nonisolated extension ImpulseSettings {
    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        let fields: [(String, WritableKeyPath<Self, Float>)] = [
            ("fKnockbackDamageMult", \.knockbackDamageMult),
            ("fKnockbackDamageBase", \.knockbackDamageBase),
            ("fKnockbackAgilMult", \.knockbackAgilityMult),
            ("fKnockbackAgilBase", \.knockbackAgilityBase),
            ("fKnockdownDamageMult", \.knockdownDamageMult),
            ("fKnockdownDamageBase", \.knockdownDamageBase),
            ("fKnockdownAgilMult", \.knockdownAgilityMult),
            ("fKnockdownAgilBase", \.knockdownAgilityBase),
            ("fExplosionForceKnockdownMinimum", \.explosionKnockdownMinimum),
            ("fExplosionKnockStateExplodeDownTime", \.knockdownTime),
            ("fGameplayImpulseScale", \.gameplayImpulseScale),
            ("fExplosionMaxImpulse", \.explosionMaxImpulse),
            ("fKnockbackForceMax", \.knockbackForceMax),
            ("fKnockbackTime", \.knockbackTime),
            ("fKnockdownCurrentHealthThreshold", \.knockdownCurrentHealthThreshold),
            ("fKnockdownBaseHealthThreshold", \.knockdownBaseHealthThreshold),
            ("fKnockdownChance", \.knockdownChance),
            ("fExplosionForceMultLinear", \.explosionLinearMult),
            ("fExplosionForceMultAngular", \.explosionAngularMult),
            ("fExplosionSourceRefMult", \.explosionSourceRefMult),
            ("fExplosionForceClutterUpBias", \.explosionUpBias),
            ("fGameplayImpulseMultBiped", \.gameplayImpulse.biped),
            ("fGameplayImpulseMultClutter", \.gameplayImpulse.clutter),
            ("fGameplayImpulseMultProp", \.gameplayImpulse.prop),
            ("fGameplayImpulseMultDebrisLarge", \.gameplayImpulse.debrisLarge),
            ("fGameplayImpulseMultTrap", \.gameplayImpulse.trap),
            ("fGameplayImpulseMinMass", \.gameplayImpulseMinMass),
            ("fProjectileKnockMultBiped", \.projectileKnock.biped),
            ("fProjectileKnockMultClutter", \.projectileKnock.clutter),
            ("fProjectileKnockMultProp", \.projectileKnock.prop),
            ("fProjectileKnockMultTrap", \.projectileKnock.trap),
            ("fProjectileKnockMinMass", \.projectileKnockMinMass),
            ("fPhysicsDamageSpeedMin", \.physicsDamageSpeedMin),
            ("fPhysicsDamageSpeedBase", \.physicsDamageSpeedBase),
            ("fPhysicsDamageSpeedMult", \.physicsDamageSpeedMult)
        ]
        for (editorID, keyPath) in fields {
            store.read(editorID, into: &settings, keyPath)
        }
        // No large-debris projectile setting exists; such debris moves as clutter.
        settings.projectileKnock.debrisLarge = settings.projectileKnock.clutter
        for index in settings.physicsDamageTiers.indices {
            store.read(
                "fPhysicsDamage\(index + 1)Mass", into: &settings, \.physicsDamageTiers[index].mass
            )
            store.read(
                "fPhysicsDamage\(index + 1)Damage",
                into: &settings, \.physicsDamageTiers[index].damage
            )
        }
        return settings
    }
}
