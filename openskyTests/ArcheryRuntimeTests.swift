// Intent to raised events to a loosed arrow (issue #196, roadmap item 15.5,
// scope point 2).
//
// The counterpart of `ProjectileRuntimeTests`: that suite owns the flight, this
// one owns the seam between the player's held button, the census-named events
// the engine raises, the events the graph fires back, and the shot that comes
// out the other end.

@testable import opensky
import simd
import Testing

@MainActor
struct ArcheryRuntimeTests {
    private static let arrow = FormID(0x0001_397D)

    private static func runtime(
        world: FakeProjectileWorld,
        bowDamage: Float = 7,
        bowSpeed: Float = 1
    ) -> ArcheryRuntime {
        let runtime = ArcheryRuntime(
            settings: .synthetic,
            projectiles: ProjectileRuntime(settings: .synthetic)
        )
        runtime.attach(world: world)
        runtime.bow = MeleeWeaponProfile(
            damage: bowDamage, reach: 1, speed: bowSpeed, weapon: FormID(0x0001_397E)
        )
        runtime.arrow = ArcheryAmmunition(
            item: arrow,
            damage: 8,
            profile: ProjectileProfile(speed: 3600, gravityFactor: 0.35, range: 60000)
        )
        return runtime
    }

    private static func held(_ drawing: Bool, dt: Float = 1.0 / 60) -> ArcheryIntent {
        ArcheryIntent(drawing: drawing, hasBowEquipped: true, deltaTime: dt)
    }

    @Test func pressingTheAttackButtonRaisesTheDrawEvent() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        runtime.acceptFrame(Self.held(true))

        #expect(world.raised == [ArcheryGraphNames.bowDrawStart])
        #expect(runtime.drawRequestCount == 1)
    }

    @Test func holdingRaisesNothingFurtherAndReleasingRaisesTheRelease() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        runtime.acceptFrame(Self.held(true))
        runtime.acceptFrame(Self.held(true))
        runtime.acceptFrame(Self.held(true))
        runtime.acceptFrame(Self.held(false))

        #expect(world.raised == [
            ArcheryGraphNames.bowDrawStart, ArcheryGraphNames.attackRelease
        ])
    }

    @Test func aPressWithNoBowEquippedRaisesNothing() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        runtime.acceptFrame(ArcheryIntent(drawing: true, hasBowEquipped: false, deltaTime: 0.1))

        #expect(world.raised.isEmpty)
        #expect(runtime.drawRequestCount == 0)
    }

    @Test func theHoldClockAccumulatesOnlyWhileDrawing() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        for _ in 0 ..< 30 {
            runtime.acceptFrame(Self.held(true))
        }
        #expect(abs(runtime.heldSeconds - 0.5) < 0.001)

        runtime.acceptFrame(Self.held(false))
        #expect(abs(runtime.heldSeconds - 0.5) < 0.001)
    }

    /// The frame the graph reports the release is the frame a projectile
    /// exists. Nothing before it puts anything in the air.
    @Test func theGraphsReleaseEventIsWhatSpawnsTheProjectile() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        runtime.acceptFrame(Self.held(true))
        runtime.handleGraphEvents([
            ArcheryGraphNames.arrowAttach, ArcheryGraphNames.bowDrawn
        ])
        #expect(runtime.projectiles.live.isEmpty)

        let launched = runtime.handleGraphEvents([ArcheryGraphNames.arrowRelease])

        #expect(launched.count == 1)
        #expect(runtime.projectiles.live.count == 1)
        #expect(world.consumed == [Self.arrow])
    }

    /// The damage a shot carries is the documented combination, fixed at
    /// launch: 7 + 8 at skill 15 is 15 * 1.075 = 16.125 at a full draw.
    @Test func theLoosedShotCarriesTheDocumentedDamageCombination() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)
        // Long enough to be past the 100% branch at speed 1 (102 frames).
        for _ in 0 ..< 130 {
            runtime.acceptFrame(Self.held(true))
        }

        let launched = runtime.handleGraphEvents([ArcheryGraphNames.arrowRelease])

        let damage = launched.first?.damage
        #expect(damage?.bowDamage == 7)
        #expect(damage?.arrowDamage == 8)
        #expect(damage?.drawFraction == 1)
        #expect(abs((damage?.applied ?? 0) - 16.125) < 0.001)
    }

    @Test func aSnapShotCarriesTheMinimumDrawFraction() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)
        runtime.acceptFrame(Self.held(true))

        let launched = runtime.handleGraphEvents([ArcheryGraphNames.arrowRelease])

        #expect(launched.first?.damage.drawFraction == ArcheryDamage.minimumDrawFraction)
        // A partial draw is slower as well as weaker.
        let speed = simd_length(launched.first?.state.velocity ?? SIMD3())
        #expect(abs(speed - 3600 * ArcheryDamage.minimumDrawFraction) < 1)
    }

    @Test func theHoldClockRestartsAfterEveryShot() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)
        for _ in 0 ..< 60 {
            runtime.acceptFrame(Self.held(true))
        }

        runtime.handleGraphEvents([ArcheryGraphNames.arrowRelease])

        #expect(runtime.heldSeconds == 0)
        #expect(abs(runtime.lastHeldSeconds - 1) < 0.001)
    }

    @Test func withNoArrowCarriedAReleaseLoosesNothing() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)
        runtime.arrow = nil

        let launched = runtime.handleGraphEvents([ArcheryGraphNames.arrowRelease])

        #expect(launched.isEmpty)
        #expect(runtime.projectiles.live.isEmpty)
        #expect(world.consumed.isEmpty)
    }

    @Test func theFullDrawFlagIsPublishedToTheGraph() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        runtime.handleGraphEvents([ArcheryGraphNames.arrowAttach])
        #expect(world.variables[ArcheryGraphNames.isBowDrawn] == .bool(false))

        runtime.handleGraphEvents([ArcheryGraphNames.bowDrawn])
        #expect(world.variables[ArcheryGraphNames.isBowDrawn] == .bool(true))
    }

    @Test func cancellingADrawRaisesTheResetEvent() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)
        runtime.acceptFrame(Self.held(true))
        runtime.handleGraphEvents([ArcheryGraphNames.arrowAttach])

        runtime.cancelDraw()

        #expect(world.raised.contains(ArcheryGraphNames.bowReset))
        #expect(runtime.heldSeconds == 0)
    }

    @Test func aCancelWithNoDrawInProgressRaisesNothing() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        runtime.cancelDraw()

        #expect(world.raised.isEmpty)
    }

    /// The dev spawn control's path: the same `loose`, without the quiver.
    @Test func aDevSpawnFiresWithoutSpendingAnArrow() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        let projectile = runtime.loose(consumesArrow: false)

        #expect(projectile != nil)
        #expect(world.consumed.isEmpty)
        #expect(world.arrowCount == 10)
        #expect(runtime.projectiles.live.count == 1)
    }

    @Test func resetForgetsTheDrawAndEmptiesTheAir() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)
        for _ in 0 ..< 30 {
            runtime.acceptFrame(Self.held(true))
        }
        runtime.handleGraphEvents([ArcheryGraphNames.arrowRelease])

        runtime.reset()

        #expect(runtime.heldSeconds == 0)
        #expect(runtime.state.phase == .idle)
        #expect(runtime.projectiles.live.isEmpty)
    }
}
