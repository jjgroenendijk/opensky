// After an arrow lands: how deep it sits, how long it stays in an actor, whether the
// target keeps it, and the notice an empty quiver shows. UESP "Skyrim:Archery".

@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
struct ProjectileArrowAfterImpactTests {
    private static let arrow = FormID(0x0001_397D)
    private static let actor = ReferenceKey.generated(7)

    private static func runtime(
        world: FakeProjectileWorld,
        arrows: ArrowSettings
    ) -> ProjectileRuntime {
        let runtime = ProjectileRuntime(settings: .synthetic, world: world)
        runtime.arrows = arrows
        return runtime
    }

    private static func fire(_ runtime: ProjectileRuntime, seconds: Float = 2) {
        runtime.fire(ProjectileShot.arrow(
            profile: ProjectileProfile(
                speed: 1000,
                gravityFactor: 0,
                range: 4000,
                collisionRadius: 2
            ),
            damage: ArcheryDamage.resolve(bowDamage: 15, arrowDamage: 0, skill: 0),
            weapon: FormID(0x0001_397E),
            ammunition: arrow
        ))
        advance(runtime, seconds: seconds)
    }

    private static func advance(_ runtime: ProjectileRuntime, seconds: Float) {
        for _ in 0 ..< Int(seconds * 60) {
            runtime.advance(by: 1.0 / 60)
        }
    }

    @Test func aStuckArrowSitsTheStickDepthPastTheContact() throws {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0002_0000))
        let shallow = Self.runtime(world: world, arrows: { var a = ArrowSettings()
            a.stickDepth = 0
            return a
        }())
        Self.fire(shallow)
        let deep = Self.runtime(world: world, arrows: .vanilla)
        Self.fire(deep)

        let positions = world.spawned.map(\.position.x)
        try #require(positions.count == 2)
        #expect(abs(positions[1] - positions[0] - 20) < 0.05)
    }

    @Test func anArrowInAnActorComesOutAfterTheMaximumAge() {
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: Self.actor, feet: SIMD3(500, 0, -64))]
        let runtime = Self.runtime(world: world, arrows: .vanilla)
        Self.fire(runtime)
        #expect(runtime.stuck.count == 1)
        #expect(runtime.attached.expiry.count == 1)

        // The arrow stuck 1.5 s before `fire` returned.
        Self.advance(runtime, seconds: 8)
        #expect(runtime.stuck.count == 1)
        Self.advance(runtime, seconds: 1)

        #expect(runtime.stuck.isEmpty)
        #expect(runtime.attached.expiry.isEmpty)
        #expect(world.removed.count == 1)
    }

    @Test func anArrowInAWallStays() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0002_0000))
        let runtime = Self.runtime(world: world, arrows: .vanilla)
        Self.fire(runtime, seconds: 30)

        #expect(runtime.stuck.count == 1)
        #expect(runtime.attached.expiry.isEmpty)
    }

    @Test func theInventoryChanceDecidesWhetherTheTargetKeepsTheArrow() {
        var always = ArrowSettings()
        always.inventoryChance = 100
        var never = ArrowSettings()
        never.inventoryChance = 0
        for (settings, expected) in [(always, [Self.actor]), (never, [])] {
            let world = FakeProjectileWorld()
            world.targets = [MeleeTarget(key: Self.actor, feet: SIMD3(500, 0, -64))]
            let runtime = Self.runtime(world: world, arrows: settings)
            Self.fire(runtime)
            #expect(world.recovered == expected)
            #expect(runtime.attached.recoveredCount == expected.count)
        }
    }

    /// Hunter's Discipline doubles the chance, so 50% with the perk always recovers.
    @Test func theShootersPerksScaleTheChance() {
        var half = ArrowSettings()
        half.inventoryChance = 50
        for (multiplier, expected) in [(Float(2), 3), (0, 0)] {
            let world = FakeProjectileWorld()
            world.recoveryMultiplier = multiplier
            world.targets = [MeleeTarget(key: Self.actor, feet: SIMD3(500, 0, -64))]
            let runtime = Self.runtime(world: world, arrows: half)
            for _ in 0 ..< 3 {
                Self.fire(runtime)
            }
            #expect(world.recovered.count == expected)
        }
    }

    @Test func anEmptyQuiverShowsTheNoticeOncePerPressAndDoesNotDraw() {
        let world = FakeProjectileWorld()
        let runtime = ArcheryRuntime(
            settings: .synthetic,
            projectiles: ProjectileRuntime(settings: .synthetic, world: world),
            world: world
        )
        runtime.bow = MeleeWeaponProfile(damage: 7, reach: 1, speed: 1, weapon: FormID(0x0001_397E))
        let press = ArcheryIntent(drawing: true, hasBowEquipped: true, deltaTime: 1.0 / 60)
        let release = ArcheryIntent(drawing: false, hasBowEquipped: true, deltaTime: 1.0 / 60)

        runtime.acceptFrame(press)
        runtime.acceptFrame(press)
        runtime.acceptFrame(release)
        runtime.acceptFrame(press)

        #expect(world.notices == ["sNoArrows", "sNoArrows"])
        #expect(world.raised.isEmpty)
        #expect(runtime.drawRequestCount == 0)
    }

    @Test func settingsComeFromTheLoadOrder() throws {
        let store = try GameSettingFixture.store([
            "fCombatMissileStickDepth": .float(5),
            "fAttachedArrowAgeMax": .float(3),
            "iArrowInventoryChance": .integer(66),
            "sNoArrows": .text("Quiver empty")
        ])
        let settings = ArrowSettings.resolve(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        #expect(settings.stickDepth == 5)
        #expect(settings.attachedAgeMax == 3)
        #expect(settings.inventoryChance == 66)
        #expect(settings.noArrowsText == "Quiver empty")
        #expect(settings.noBoltsText == "sNoBolts")
    }
}
