// How an arrow ends its flight: it sticks in a material that holds arrows and bounces
// off any other, a shield's deflection bounces it, a bolt sits less deep, and an actor
// shows at most three. See docs/engine/projectiles.md#pick-up-bounce-and-stick-in-the-game.

@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
struct ProjectileBounceTests {
    private static let wood = FormID(0x0001_0001)
    private static let stone = FormID(0x0001_0002)
    private static let actor = ReferenceKey.generated(7)

    private static func runtime(
        world: FakeProjectileWorld, holding: Set<FormID>? = [wood]
    ) -> ProjectileRuntime {
        let runtime = ProjectileRuntime(settings: .synthetic, world: world)
        runtime.arrows.holdingMaterials = holding
        return runtime
    }

    private static func fire(_ runtime: ProjectileRuntime, bolt: Bool = false, seconds: Float = 1) {
        var shot = ProjectileShot.arrow(
            profile: ProjectileProfile(
                speed: 1000,
                gravityFactor: 0,
                range: 4000,
                collisionRadius: 2
            ),
            damage: ArcheryDamage.resolve(bowDamage: 15, arrowDamage: 0, skill: 0),
            weapon: FormID(0x0001_397E),
            ammunition: FormID(0x0001_397D)
        )
        shot.isBolt = bolt
        runtime.fire(shot)
        advance(runtime, seconds: seconds)
    }

    private static func advance(_ runtime: ProjectileRuntime, seconds: Float) {
        for _ in 0 ..< Int(seconds * 60) {
            runtime.advance(by: 1.0 / 60)
        }
    }

    @Test func anArrowSticksInAMaterialThatHoldsArrows() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(
            x: 500,
            reference: FormID(0x0002_0000),
            material: Self.wood
        )
        let runtime = Self.runtime(world: world)

        Self.fire(runtime)

        #expect(runtime.stuck.count == 1)
        #expect(runtime.live.isEmpty)
    }

    @Test func anArrowBouncesOffOtherMaterialsAtATenthOfItsSpeed() throws {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(
            x: 500,
            reference: FormID(0x0002_0000),
            material: Self.stone
        )
        let runtime = Self.runtime(world: world)

        Self.fire(runtime)

        #expect(runtime.stuck.isEmpty)
        let bounced = try #require(runtime.live.first)
        #expect(bounced.hasBounced)
        // The shot left 2 degrees up, the archery tilt, and comes back the same way.
        #expect(abs(simd_length(bounced.state.velocity) - 100) < 0.01)
        #expect(bounced.state.velocity.x < -99)
        #expect(runtime.trace.last?.stuck == false)
        let readout = runtime.readout
        #expect(readout.bouncing == 1)
        #expect(readout.landings.last?.bounced == true)
        #expect(readout.landings.last?.material == Self.stone)
    }

    @Test func withoutMaterialDataEveryArrowSticks() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(
            x: 500,
            reference: FormID(0x0002_0000),
            material: Self.stone
        )
        let runtime = Self.runtime(world: world, holding: nil)

        Self.fire(runtime)

        #expect(runtime.stuck.count == 1)
    }

    @Test func aBouncedArrowLiesWhereItLandsAndDoesNoHarm() throws {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(
            x: 500,
            reference: FormID(0x0002_0000),
            material: Self.stone
        )
        let runtime = Self.runtime(world: world)
        Self.fire(runtime)
        world.wall = FakeProjectileWorld.Wall(
            x: 300,
            reference: FormID(0x0002_0001),
            material: Self.stone
        )

        Self.advance(runtime, seconds: 3)

        #expect(runtime.live.isEmpty)
        let lying = try #require(world.spawned.first)
        #expect(abs(lying.position.x - 300) < 0.01)
    }

    @Test func aBouncedArrowFallingOnAnActorLeavesNothing() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(
            x: 500,
            reference: FormID(0x0002_0000),
            material: Self.stone
        )
        let runtime = Self.runtime(world: world)
        Self.fire(runtime)
        world.targets = [MeleeTarget(key: Self.actor, feet: SIMD3(300, 0, -64))]

        Self.advance(runtime, seconds: 3)

        #expect(runtime.live.isEmpty)
        #expect(runtime.stuck.isEmpty)
        #expect(world.damage[Self.actor] == nil)
    }

    @Test func aDeflectedArrowBouncesOffTheShield() {
        let world = FakeProjectileWorld()
        world.deflects = true
        world.targets = [MeleeTarget(key: Self.actor, feet: SIMD3(500, 0, -64))]
        let runtime = Self.runtime(world: world)

        Self.fire(runtime, seconds: 0.6)

        #expect(runtime.stuck.isEmpty)
        #expect(runtime.live.first?.hasBounced == true)
    }

    @Test func aBoltSitsLessDeepThanAnArrow() throws {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(
            x: 500,
            reference: FormID(0x0002_0000),
            material: Self.wood
        )
        Self.fire(Self.runtime(world: world))
        Self.fire(Self.runtime(world: world), bolt: true)

        let depths = world.spawned.map { $0.position.x - 500 }
        try #require(depths.count == 2)
        #expect(abs(depths[0] - 20) < 0.05)
        #expect(abs(depths[1] - 5) < 0.05)
    }

    @Test func anActorShowsAtMostThreeArrows() {
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: Self.actor, feet: SIMD3(500, 0, -64))]
        let runtime = Self.runtime(world: world)

        for _ in 0 ..< 4 {
            Self.fire(runtime)
        }

        #expect(runtime.stuck.count == 3)
        #expect(world.removed.count == 1)
        #expect(runtime.attached.holder.count == 3)
    }

    @Test func theArrowFlagOfAMaterialIsBitOne() {
        let holds = MaterialType(formID: Self.wood, materialName: nil, flags: 0x2)
        let slips = MaterialType(formID: Self.stone, materialName: nil, flags: 0x1)
        let index = MaterialTypeIndex(materials: [holds, slips], landTextureMaterials: [:])

        #expect(index.arrowHoldingMaterials == [Self.wood])
        var settings = ArrowSettings.resolve(store: GameSettingStore(plugins: []), materials: index)
        #expect(settings.holds(material: Self.wood))
        #expect(!settings.holds(material: Self.stone))
        #expect(settings.holds(material: nil))
        settings.holdingMaterials = nil
        #expect(settings.holds(material: Self.stone))
    }

    @Test func aNPCSpellAimsWithNoiseOnlyWhenItIsNotConcentration() {
        let runtime = ProjectileRuntime(settings: .synthetic, world: nil)
        let point = SIMD3<Float>(100, 0, 0)

        #expect(runtime.npcSpellAim(at: point, concentration: true) == point)
        let aimed = runtime.npcSpellAim(at: point, concentration: false)
        let reach: Float = 0.5 * 16 * 1.7321 + 0.001
        #expect(simd_length(aimed - point) <= reach)
    }
}
