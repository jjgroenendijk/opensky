// Hit knockback, explosion and projectile pushes, and physics damage, with the
// install's setting values (docs/engine/impulses.md).

import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import simd
import Testing

struct ImpulseRulesTests {
    private let settings = ImpulseSettings.vanilla

    private func crate(
        mass: Float = 10, kind: ImpulseBodyKind = .clutter,
        position: SIMD3<Float> = SIMD3(100, 0, 0)
    ) -> ImpulseBody {
        ImpulseBody(
            key: .generated(1), reference: FormID(0x1234), position: position,
            mass: mass, boundingRadius: 10, kind: kind
        )
    }

    @Test func aHitSlidesItsTargetByTheAgilityScaledDamage() throws {
        let knock = try #require(HitKnockback.knock(
            damage: 20, health: (current: 100, maximum: 100), roll: 0.9, settings: settings
        ))
        // (20 * 5 + 50) * (-0.008 * 50 + 1) is 90 units, spread over 0.3 seconds.
        #expect(abs(knock.speed - 90 / 0.3) < 0.01)
        #expect(!knock.isKnockdown)
    }

    @Test func aHeavyHitSlidesAtMostTheMaximum() {
        #expect(HitKnockback.distance(damage: 500, settings: settings) == 128)
    }

    @Test func aHitOverHalfTheCurrentHealthRollsTheKnockdownChance() throws {
        // The chance is min(20 * 0.3 / 50, 0.25), 0.12, rolled per mille.
        let low = try #require(HitKnockback.knock(
            damage: 20, health: (current: 30, maximum: 100), roll: 0.11, settings: settings
        ))
        let high = try #require(HitKnockback.knock(
            damage: 20, health: (current: 30, maximum: 100), roll: 0.12, settings: settings
        ))
        #expect(low.isKnockdown)
        #expect(!high.isKnockdown)
    }

    @Test func theKnockdownChanceStopsAtItsCap() {
        #expect(HitKnockback.knocksDown(
            damage: 70, health: (current: 120, maximum: 1000), roll: 0.24, settings: settings
        ))
        #expect(!HitKnockback.knocksDown(
            damage: 70, health: (current: 120, maximum: 1000), roll: 0.25, settings: settings
        ))
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

    @Test func anExplosionPushesAwayWithTheSameForceAtAnyDistance() throws {
        let blast = ImpulseBlast(force: 6, radius: 320, center: .zero)
        let near = try #require(GameplayImpulse.explosion(
            blast, on: (crate(), false), spin: .zero, settings: settings
        ))
        let far = try #require(GameplayImpulse.explosion(
            blast, on: (crate(position: SIMD3(300, 0, 0)), false), spin: .zero,
            settings: settings
        ))
        #expect(near.linear.x > 0)
        #expect(abs(near.linear.z) < 0.001)
        // 6 force times 150 is 900, for clutter at full mass.
        #expect(abs(simd_length(near.linear) - 900) < 0.01)
        #expect(near.linear == far.linear)
    }

    @Test func anExplosionLiftsABipedBody() throws {
        let blast = ImpulseBlast(force: 6, radius: 320, center: .zero)
        let push = try #require(GameplayImpulse.explosion(
            blast, on: (crate(kind: .biped), false), spin: .zero, settings: settings
        ))
        #expect(abs(push.linear.z / push.linear.x - 0.5) < 0.001)
    }

    @Test func thePropAndSourceSettingsScaleTheExplosionPush() throws {
        let blast = ImpulseBlast(force: 6, radius: 320, center: .zero)
        let clutter = try #require(GameplayImpulse.explosion(
            blast, on: (crate(), false), spin: .zero, settings: settings
        ))
        let prop = try #require(GameplayImpulse.explosion(
            blast, on: (crate(kind: .prop), false), spin: .zero, settings: settings
        ))
        let source = try #require(GameplayImpulse.explosion(
            blast, on: (crate(), true), spin: .zero, settings: settings
        ))
        #expect(abs(simd_length(prop.linear) / simd_length(clutter.linear) - 0.1) < 0.001)
        #expect(abs(simd_length(source.linear) / simd_length(clutter.linear) - 3) < 0.001)
    }

    @Test func anExplosionPushStopsAtTheImpulseCap() throws {
        let blast = ImpulseBlast(force: 100, radius: 320, center: .zero)
        let push = try #require(GameplayImpulse.explosion(
            blast, on: (crate(), false), spin: SIMD3(1, -1, 0.5), settings: settings
        ))
        #expect(abs(simd_length(push.linear) - 8000) < 0.1)
        #expect(abs(push.angular.x - 8000 * GameplayImpulse.havokScale) < 1)
        #expect(abs(push.angular.z - 4000 * GameplayImpulse.havokScale) < 1)
    }

    @Test func aLightBodyMovesAsTheMinimumMass() throws {
        let blast = ImpulseBlast(force: 6, radius: 320, center: .zero)
        let light = try #require(GameplayImpulse.explosion(
            blast, on: (crate(mass: 1), false), spin: .zero, settings: settings
        ))
        let heavy = try #require(GameplayImpulse.explosion(
            blast, on: (crate(mass: 10), false), spin: .zero, settings: settings
        ))
        // A 1 kg body changes speed as a 5 kg one does, so its impulse is a fifth.
        #expect(abs(simd_length(light.linear) / simd_length(heavy.linear) - 0.2) < 0.001)
    }

    @Test func anExplosionOutsideItsRadiusPushesNothing() {
        let blast = ImpulseBlast(force: 6, radius: 50, center: .zero)
        #expect(GameplayImpulse.explosion(
            blast, on: (crate(), false), spin: .zero, settings: settings
        ) == nil)
    }

    @Test func theExplosionFlagsPickTheKnockdownMode() {
        #expect(ExplosionKnockdown(flags: 0x47) == .always)
        #expect(ExplosionKnockdown(flags: 0x149) == .byFormula)
        #expect(ExplosionKnockdown(flags: 0x1) == .never)
        #expect(ExplosionKnockdown(flags: nil) == .never)
    }

    @Test func anExplosionKnocksDownOnlyNearItsCentre() {
        let blast = ImpulseBlast(force: 6, radius: 100, center: .zero)
        let health: (current: Float, maximum: Float) = (100, 100)
        // The falloff 1 - (d / R)^2 must pass 0.15: 90 units gives 0.19, 95 gives 0.0975.
        #expect(GameplayImpulse.explosionKnocksDown(
            blast, knockdown: (.always, 90),
            hit: KnockdownHit(damage: 0, health: health, roll: 1), settings: settings
        ))
        #expect(!GameplayImpulse.explosionKnocksDown(
            blast, knockdown: (.always, 95),
            hit: KnockdownHit(damage: 0, health: health, roll: 1), settings: settings
        ))
        #expect(!GameplayImpulse.explosionKnocksDown(
            blast, knockdown: (.never, 0),
            hit: KnockdownHit(damage: 0, health: health, roll: 0), settings: settings
        ))
        #expect(GameplayImpulse.explosionKnocksDown(
            blast, knockdown: (.byFormula, 0),
            hit: KnockdownHit(damage: 80, health: health, roll: 1), settings: settings
        ))
    }

    @Test func aProjectilePushesAlongItsFlight() throws {
        let push = try #require(GameplayImpulse.projectile(
            impactForce: 1, impact: (SIMD3(0, 3600, 0), SIMD3(100, 0, 0)), body: crate(),
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
