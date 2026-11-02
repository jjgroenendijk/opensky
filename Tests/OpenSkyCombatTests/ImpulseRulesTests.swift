// Hit knockback, explosion and projectile pushes, and physics damage, with the
// install's setting values (docs/engine/impulses.md).

import OpenSkyCombat
import OpenSkyFormatsESM
import simd
import Testing

struct ImpulseRulesTests {
    private let settings = ImpulseSettings.vanilla

    private func crate(mass: Float = 10, kind: ImpulseBodyKind = .clutter) -> ImpulseBody {
        ImpulseBody(
            key: .generated(1), reference: FormID(0x1234), position: SIMD3(100, 0, 0),
            mass: mass, boundingRadius: 10, kind: kind
        )
    }

    @Test func aWeakHitDoesNotKnockBack() {
        let knock = HitKnockback.knock(
            damage: 20, health: (current: 100, maximum: 100), roll: 0.9, settings: settings
        )
        #expect(knock == nil)
    }

    @Test func aHitOfHalfTheCurrentHealthPushesByItsDamage() throws {
        let knock = try #require(HitKnockback.knock(
            damage: 20, health: (current: 40, maximum: 100), roll: 0.9, settings: settings
        ))
        // 20 damage times 5 is 100 units, spread over 0.3 seconds.
        #expect(abs(knock.speed - 100 / 0.3) < 0.01)
        #expect(!knock.isKnockdown)
    }

    @Test func aLowRollKnocksDownTheFullDistance() throws {
        let knock = try #require(HitKnockback.knock(
            damage: 20, health: (current: 40, maximum: 100), roll: 0.1, settings: settings
        ))
        #expect(knock.isKnockdown)
        #expect(abs(knock.speed - 128 / 0.3) < 0.01)
    }

    @Test func aHitOfThreeQuartersOfBaseHealthAlwaysKnocksDown() throws {
        let knock = try #require(HitKnockback.knock(
            damage: 80, health: (current: 100, maximum: 100), roll: 0.99, settings: settings
        ))
        #expect(knock.isKnockdown)
    }

    @Test func aKillingHitLeavesThePushToTheDeathRagdoll() {
        let knock = HitKnockback.knock(
            damage: 50, health: (current: 40, maximum: 100), roll: 0, settings: settings
        )
        #expect(knock == nil)
    }

    @Test func aRangedHitPushesByTheBipedProjectileSetting() throws {
        let knock = try #require(HitKnockback.knock(
            damage: 20, health: (current: 40, maximum: 100), roll: 0.9,
            scale: settings.projectileKnock.biped, settings: settings
        ))
        #expect(abs(knock.speed - 25 / 0.3) < 0.01)
    }

    @Test func anExplosionPushesAwayAndUp() throws {
        let blast = ImpulseBlast(force: 60, radius: 320, center: .zero)
        let push = try #require(GameplayImpulse.explosion(
            blast, on: crate(), isSource: false, settings: settings
        ))
        #expect(push.linear.x > 0)
        #expect(push.linear.z > 0)
        // The nearest side is 90 units away: 60 * (1 - 90 / 320) in Havok units.
        let expected = 60 * (1 - 90 / Float(320)) * GameplayImpulse.havokScale
        #expect(abs(simd_length(push.linear) - expected) < 0.1)
    }

    @Test func thePropAndSourceSettingsScaleTheExplosionPush() throws {
        let blast = ImpulseBlast(force: 60, radius: 320, center: .zero)
        let clutter = try #require(GameplayImpulse.explosion(
            blast, on: crate(), isSource: false, settings: settings
        ))
        let prop = try #require(GameplayImpulse.explosion(
            blast, on: crate(kind: .prop), isSource: false, settings: settings
        ))
        let source = try #require(GameplayImpulse.explosion(
            blast, on: crate(), isSource: true, settings: settings
        ))
        #expect(abs(simd_length(prop.linear) / simd_length(clutter.linear) - 0.1) < 0.001)
        #expect(abs(simd_length(source.linear) / simd_length(clutter.linear) - 3) < 0.001)
    }

    @Test func aLightBodyMovesAsTheMinimumMass() throws {
        let blast = ImpulseBlast(force: 60, radius: 320, center: .zero)
        let light = try #require(GameplayImpulse.explosion(
            blast, on: crate(mass: 1), isSource: false, settings: settings
        ))
        let heavy = try #require(GameplayImpulse.explosion(
            blast, on: crate(mass: 10), isSource: false, settings: settings
        ))
        // A 1 kg body changes speed as a 5 kg one does, so its impulse is a fifth.
        #expect(abs(simd_length(light.linear) / simd_length(heavy.linear) - 0.2) < 0.001)
    }

    @Test func anExplosionOutsideItsRadiusPushesNothing() {
        let blast = ImpulseBlast(force: 60, radius: 50, center: .zero)
        #expect(GameplayImpulse.explosion(
            blast, on: crate(), isSource: false, settings: settings
        ) == nil)
        #expect(GameplayImpulse.explosionKnock(blast, distance: 60, settings: settings) == 0)
    }

    @Test func anExplosionKnocksAnActorByTheBipedSetting() {
        let blast = ImpulseBlast(force: 60, radius: 320, center: .zero)
        let speed = GameplayImpulse.explosionKnock(blast, distance: 0, settings: settings)
        #expect(abs(speed - 60 * 0.04 * GameplayImpulse.havokScale) < 0.01)
    }

    @Test func aProjectilePushesAlongItsFlight() throws {
        let push = try #require(GameplayImpulse.projectile(
            impactForce: 1, flight: SIMD3(0, 3600, 0), at: SIMD3(100, 0, 0), body: crate(),
            settings: settings
        ))
        #expect(push.linear.y > 0)
        #expect(abs(simd_length(push.linear) - 0.15 * GameplayImpulse.havokScale) < 0.01)
    }

    @Test func physicsDamageNeedsSpeedAndMass() {
        #expect(PhysicsDamage.damage(mass: 60, speed: 400, settings: settings) == 0)
        #expect(PhysicsDamage.damage(mass: 10, speed: 1000, settings: settings) == 0)
        let damage = PhysicsDamage.damage(mass: 60, speed: 1000, settings: settings)
        #expect(abs(damage - 5 * 1.1) < 0.0001)
    }

    @Test func aBodyKindFollowsItsCollisionLayer() {
        #expect(ImpulseBodyKind(collisionLayer: 4) == .clutter)
        #expect(ImpulseBodyKind(collisionLayer: 10) == .prop)
        #expect(ImpulseBodyKind(collisionLayer: 20) == .debrisLarge)
        #expect(ImpulseBodyKind(collisionLayer: 14) == .trap)
        #expect(ImpulseBodyKind(collisionLayer: 8) == .biped)
    }
}
