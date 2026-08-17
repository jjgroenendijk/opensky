// Spell projectiles through the arrow pipeline (issue #471, roadmap item 19.8,
// scope points 1, 2 and 6): one shot model, PROJ-driven flight, and what a
// landed spell reaches.
//
// The fake world is the archery suites' own `FakeProjectileWorld`, which is the
// point: a spell projectile that needed a second fake would be a second flight
// engine wearing the first one's name.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct ProjectileSpellTests {
    private static let victim = ReferenceKey.plugin(name: "base.esm", objectID: 0x0900)
    private static let bystander = ReferenceKey.plugin(name: "base.esm", objectID: 0x0901)

    private static func runtime(world: FakeProjectileWorld) -> ProjectileRuntime {
        let runtime = ProjectileRuntime(settings: .synthetic)
        runtime.attach(world: world)
        return runtime
    }

    /// A flat, fast profile so the impact point is exactly on the aim ray.
    private static func profile(range: Float = 4000) -> ProjectileProfile {
        ProjectileProfile(speed: 1000, gravityFactor: 0, range: range, collisionRadius: 2)
    }

    private static func payload(
        area: UInt32 = 0,
        isHostile: Bool = true,
        magnitude: Float = 25
    ) -> SpellPayload {
        SpellPayload(
            spell: .plugin(name: "base.esm", objectID: 0x0230),
            sourcePlugin: "Base.esm",
            caster: .player,
            entries: [MagicItemEffect(
                effect: FormID(0x0012),
                magnitude: magnitude,
                area: area,
                duration: 0,
                conditions: ConditionList()
            )],
            isHostile: isHostile,
            ignoresResistance: false,
            projectile: FormID(0x0020),
            name: "Firebolt"
        )
    }

    @discardableResult
    private static func advance(
        _ runtime: ProjectileRuntime,
        seconds: Float
    ) -> [ProjectileTrace] {
        var traces: [ProjectileTrace] = []
        var elapsed: Float = 0
        while elapsed < seconds {
            traces += runtime.advance(by: 1.0 / 60)
            elapsed += 1.0 / 60
        }
        return traces
    }

    // MARK: - Flight

    /// A spell projectile flies on the PROJ's own numbers, spends no
    /// ammunition, and does not take the bow's tilt-up angle — it leaves
    /// straight down the aim ray.
    @Test func aSpellProjectileFliesOnItsPROJAndSpendsNoAmmunition() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        let launched = runtime.fire(
            ProjectileShot.spell(profile: Self.profile(), payload: Self.payload())
        )

        let projectile = launched
        #expect(projectile != nil)
        #expect(world.consumed.isEmpty)
        #expect(world.arrowCount == 10)
        #expect(simd_length(projectile?.state.velocity ?? SIMD3()) == 1000)
        // Straight down the camera ray: the archery tilt is a bow's own
        // compensation for arrow drop.
        #expect(abs((projectile?.launchDirection.z ?? 1)) < 0.0001)
    }

    /// An arrow still takes the tilt, so generalizing the shot model did not
    /// quietly change the archery path.
    @Test func anArrowStillTakesTheArcheryTilt() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)

        let launched = runtime.fire(ProjectileShot.arrow(
            profile: Self.profile(),
            damage: ArcheryDamage.resolve(bowDamage: 15, arrowDamage: 0, skill: 0),
            ammunition: FormID(0x0001_397D)
        ))

        #expect(world.consumed.count == 1)
        #expect((launched?.launchDirection.z ?? 0) > 0)
    }

    /// A spell projectile leaves nothing standing in the world: nothing sticks
    /// and nothing is spawned.
    @Test func aSpellProjectileNeverSticks() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0000_0100))
        let runtime = Self.runtime(world: world)
        runtime.fire(ProjectileShot.spell(profile: Self.profile(), payload: Self.payload()))

        let traces = Self.advance(runtime, seconds: 1)

        #expect(traces.first?.outcome == .hitStatic)
        #expect(traces.first?.stuck == false)
        #expect(world.spawned.isEmpty)
    }

    // MARK: - Hit application

    /// A spell projectile that strikes an actor hands that actor to the world
    /// as the direct target, and takes no health off itself — the effect
    /// runtime does that.
    @Test func strikingAnActorHandsItToTheSpellHitSeam() {
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: Self.victim, feet: SIMD3(400, 0, -60))]
        let runtime = Self.runtime(world: world)
        runtime.fire(ProjectileShot.spell(profile: Self.profile(), payload: Self.payload()))

        let traces = Self.advance(runtime, seconds: 1)

        #expect(traces.first?.outcome == .hitActor)
        #expect(traces.first?.appliedDamage == 0)
        #expect(world.damage.isEmpty)
        let hit = world.spellHits.first
        #expect(hit?.targets.map(\.key) == [Self.victim])
        #expect(hit?.targets.first?.isDirect == true)
        #expect(traces.first?.spellHit?.targetCount == 1)
    }

    /// An area entry catches a bystander standing near the impact point, and
    /// the bystander is not the direct target.
    @Test func anAreaEntryCatchesABystander() {
        let world = FakeProjectileWorld()
        world.targets = [
            MeleeTarget(key: Self.victim, feet: SIMD3(400, 0, -60)),
            MeleeTarget(key: Self.bystander, feet: SIMD3(430, 60, -60))
        ]
        let runtime = Self.runtime(world: world)
        runtime.fire(ProjectileShot.spell(
            profile: Self.profile(), payload: Self.payload(area: 15)
        ))

        Self.advance(runtime, seconds: 1)

        let hit = world.spellHits.first
        #expect(hit?.targets.count == 2)
        #expect(hit?.targets.last?.key == Self.bystander)
        #expect(hit?.targets.last?.isDirect == false)
    }

    /// A point spell that struck a wall reaches nobody and applies nothing,
    /// rather than applying to whoever happened to be nearest.
    @Test func aPointSpellThatStruckGeometryAppliesNothing() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0000_0100))
        world.targets = [MeleeTarget(key: Self.victim, feet: SIMD3(520, 0, -60))]
        let runtime = Self.runtime(world: world)
        runtime.fire(ProjectileShot.spell(profile: Self.profile(), payload: Self.payload()))

        let traces = Self.advance(runtime, seconds: 1)

        #expect(world.spellHits.isEmpty)
        #expect(traces.first?.spellHit == nil)
    }

    /// An area spell that struck a wall still catches whoever was standing by
    /// it, all of them as bystanders.
    @Test func anAreaSpellThatStruckGeometryStillCatchesTheActorsNearIt() {
        let world = FakeProjectileWorld()
        world.wall = FakeProjectileWorld.Wall(x: 500, reference: FormID(0x0000_0100))
        world.targets = [MeleeTarget(key: Self.victim, feet: SIMD3(520, 0, -60))]
        let runtime = Self.runtime(world: world)
        runtime.fire(ProjectileShot.spell(
            profile: Self.profile(), payload: Self.payload(area: 15)
        ))

        Self.advance(runtime, seconds: 1)

        let hit = world.spellHits.first
        #expect(hit?.targets.map(\.key) == [Self.victim])
        #expect(hit?.targets.first?.isDirect == false)
    }

    // MARK: - Combat consequences

    /// A hostile spell hit provokes its target the way an arrow does; a
    /// restorative one does not, so healing a follower at range starts no
    /// fight (scope point 6).
    @Test func onlyAHostileSpellHitProvokes() {
        for hostile in [true, false] {
            let world = FakeProjectileWorld()
            world.targets = [MeleeTarget(key: Self.victim, feet: SIMD3(400, 0, -60))]
            let runtime = Self.runtime(world: world)
            runtime.fire(ProjectileShot.spell(
                profile: Self.profile(), payload: Self.payload(isHostile: hostile)
            ))

            let traces = Self.advance(runtime, seconds: 1)

            #expect(traces.first?.provokes == hostile)
        }
    }

    /// Every arrow provokes, whatever it hit — the behaviour item 15.5 landed,
    /// unchanged.
    @Test func anArrowHitStillProvokes() {
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: Self.victim, feet: SIMD3(400, 0, -60))]
        let runtime = Self.runtime(world: world)
        runtime.fire(ProjectileShot.arrow(
            profile: Self.profile(),
            damage: ArcheryDamage.resolve(bowDamage: 15, arrowDamage: 0, skill: 0),
            ammunition: FormID(0x0001_397D)
        ))

        let traces = Self.advance(runtime, seconds: 1)

        #expect(traces.first?.provokes == true)
        #expect(traces.first?.appliedDamage ?? 0 > 0)
    }

    /// A projectile that expired in the air reached nobody, so it provokes
    /// nobody.
    @Test func aProjectileThatExpiredProvokesNobody() {
        let world = FakeProjectileWorld()
        let runtime = Self.runtime(world: world)
        runtime.fire(ProjectileShot.spell(
            profile: Self.profile(range: 100), payload: Self.payload()
        ))

        let traces = Self.advance(runtime, seconds: 1)

        #expect(traces.first?.outcome == .outOfRange)
        #expect(traces.first?.provokes == false)
    }
}
