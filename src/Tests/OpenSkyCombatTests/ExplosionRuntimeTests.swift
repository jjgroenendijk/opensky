// The explosion runtime over a synthetic EXPL plugin: falloff damage, sounds,
// the image-space strength, hazard and debris placement, seeded debris, and a
// projectile's timer and proximity detonation.

import Foundation
@testable import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyMagicInterface
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
final class FakeExplosionWorld: ExplosionWorld {
    var targets: [MeleeTarget] = []
    var viewer: SIMD3<Float>?
    private(set) var damage: [ReferenceKey: Float] = [:]
    private(set) var sounds: [ReferenceKey] = []
    private(set) var modifiers: [(ReferenceKey, Float)] = []
    private(set) var hazards: [ReferenceKey] = []
    private(set) var models: [String] = []
    private(set) var lights: [ReferenceKey] = []
    private(set) var impacts: [ReferenceKey] = []
    private(set) var detectionEvents: [ReferenceKey] = []
    struct EnchantmentCast {
        let enchantment: ReferenceKey
        let shooter: ReferenceKey?
        let targets: [ReferenceKey]
    }

    private(set) var enchantments: [EnchantmentCast] = []

    func castExplosionEnchantment(
        _ enchantment: ReferenceKey, from shooter: ReferenceKey?, on targets: [ReferenceKey]
    ) -> [ReferenceKey] {
        enchantments.append(EnchantmentCast(
            enchantment: enchantment,
            shooter: shooter,
            targets: targets
        ))
        return targets
    }

    func explosionTargets() -> [MeleeTarget] {
        targets
    }

    func explosionViewer() -> SIMD3<Float>? {
        viewer
    }

    func applyExplosionDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        damage[target, default: 0] += amount
        return true
    }

    func playExplosionSound(_ sound: ReferenceKey, at position: SIMD3<Float>) {
        sounds.append(sound)
    }

    func startExplosionImageSpace(_ modifier: ReferenceKey, strength: Float) {
        modifiers.append((modifier, strength))
    }

    func placeExplosionHazard(_ hazard: ReferenceKey, at position: SIMD3<Float>) -> Bool {
        hazards.append(hazard)
        return true
    }

    func showExplosionModel(_ path: String, at position: SIMD3<Float>) {
        models.append(path)
    }

    func showExplosionLight(_ light: ReferenceKey, at position: SIMD3<Float>) {
        lights.append(light)
    }

    func playExplosionImpact(_ dataSet: ReferenceKey, at position: SIMD3<Float>) {
        impacts.append(dataSet)
    }

    func noteExplosionSound(owner: ReferenceKey, level _: UInt32?, at _: SIMD3<Float>) {
        detectionEvents.append(owner)
    }
}

/// A spell's or a script's blast makes a sound event only with an owner; a projectile's
/// blast is its shooter's event already (docs/engine/detection-events.md).
@MainActor
struct ExplosionDetectionEventTests {
    @Test func onlyAnOwnedBlastThatNoProjectileMadeIsAnEvent() {
        let world = FakeExplosionWorld()
        let runtime = ExplosionRuntime(world: world)
        let spec = ExplosionSpec(name: "Blast", damage: 0, radius: 100)
        let owner = ReferenceKey.generated(7)
        runtime.detonate(spec, at: .zero, cause: .script)
        runtime.detonate(
            spec,
            at: .zero,
            cause: .projectile,
            origin: ExplosionOrigin(shooter: owner)
        )
        #expect(world.detectionEvents.isEmpty)
        runtime.detonate(spec, at: .zero, cause: .spell, origin: ExplosionOrigin(shooter: owner))
        #expect(world.detectionEvents == [owner])
    }
}

@MainActor
struct ExplosionRuntimeTests {
    private typealias Fixture = ESMFixture
    static let plugin = "Effects.esm"
    static let npc = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x700)

    static func explosion(
        _ formID: UInt32, placed: UInt32, sound: UInt32 = 0, light: UInt32 = 0, impacts: UInt32 = 0
    ) -> Data {
        let links = Fixture.u32(light, sound, 0, impacts, placed, 0)
        return Fixture.recordBytes("EXPL", formID: formID, fields: [
            ("EDID", Fixture.zstring("TestBlast\(formID)")),
            ("MODL", Fixture.zstring("fx/blast.nif")),
            ("MNAM", Fixture.u32(0x950)),
            ("DATA", links + Fixture.f32(400, 50, 200, 1000))
        ])
    }

    static func records() throws -> EffectRecordStore {
        let file = try Fixture.plugin(records: [
            explosion(0x900, placed: 0x901, sound: 0x902, light: 0x903, impacts: 0x904),
            explosion(0x910, placed: 0x911),
            Fixture.recordBytes("EXPL", formID: 0x920, fields: [
                ("EDID", Fixture.zstring("TestFeetBlast")),
                ("EITM", Fixture.u32(0x921)),
                (
                    "DATA",
                    Fixture.u32(0, 0, 0, 0, 0, 0) + Fixture.f32(0, 0, 10, 5, 0)
                        + Fixture.u32(0)
                )
            ]),
            Fixture.recordBytes("HAZD", formID: 0x901, fields: [("EDID", Fixture.zstring("Fire"))]),
            Fixture.recordBytes("DEBR", formID: 0x911, fields: [
                ("DATA", Fixture.u8(70) + Fixture.zstring("rock01.nif") + Fixture.u8(1)),
                ("DATA", Fixture.u8(30) + Fixture.zstring("rock02.nif") + Fixture.u8(0))
            ])
        ])
        return EffectRecordStore(plugins: [(name: plugin, file: file)])
    }

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: plugin.lowercased(), objectID: objectID)
    }

    static func runtime(world: FakeExplosionWorld) throws -> ExplosionRuntime {
        try ExplosionRuntime(records: records(), itemPlugin: plugin, world: world)
    }

    @Test func damageFallsOffWithTheSquareOfTheDistance() {
        #expect(ExplosionFalloff.damage(50, radius: 200, distance: 0) == 50)
        #expect(ExplosionFalloff.damage(50, radius: 200, distance: 100) == 37.5)
        #expect(ExplosionFalloff.damage(50, radius: 200, distance: 250) == 0)
        #expect(ExplosionFalloff.damage(50, radius: 0, distance: 0) == 50)
        #expect(ExplosionFalloff.imageSpaceStrength(radius: 0, distance: 900) == 1)
        #expect(ExplosionFalloff.imageSpaceStrength(radius: 1000, distance: 250) == 0.9375)
    }

    @Test func aDetonationDamagesSoundsAndPlacesItsHazard() throws {
        let world = FakeExplosionWorld()
        world.targets = [
            MeleeTarget(key: Self.npc, feet: SIMD3(100, 0, 0)),
            MeleeTarget(key: .player, feet: SIMD3(900, 0, 0))
        ]
        world.viewer = SIMD3(250, 0, 60)
        let runtime = try Self.runtime(world: world)
        let spec = try #require(runtime.spec(for: Self.key(0x900)))
        #expect(spec.placement == .hazard(Self.key(0x901)))
        let report = runtime.detonate(spec, at: SIMD3(0, 0, 60), cause: .debug)
        #expect(world.damage == [Self.npc: 37.5])
        #expect(world.sounds == [Self.key(0x902)])
        #expect(world.hazards == [Self.key(0x901)])
        #expect(world.models == ["fx/blast.nif"])
        #expect(world.lights == [Self.key(0x903)])
        #expect(world.impacts == [Self.key(0x904)])
        #expect(world.modifiers.first?.1 == 0.9375)
        #expect(report.hazardPlaced)
        #expect(!report.swapApplied)
        #expect(runtime.detonationTotal == 1)
    }

    @Test func aBlastInFeetCastsItsEnchantmentOnEveryActorItReaches() throws {
        let world = FakeExplosionWorld()
        let shooter = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x701)
        world.targets = [
            MeleeTarget(key: shooter, feet: SIMD3(50, 0, 0)),
            MeleeTarget(key: Self.npc, feet: SIMD3(200, 0, 0)),
            MeleeTarget(key: .player, feet: SIMD3(300, 0, 0))
        ]
        let runtime = try Self.runtime(world: world)
        let spec = try #require(runtime.spec(for: Self.key(0x920)))
        #expect(spec.radius == 220)
        #expect(spec.imageSpaceRadius == 110)
        #expect(spec.enchantment == Self.key(0x921))
        let report = runtime.detonate(
            spec, at: SIMD3(0, 0, 60), cause: .debug, origin: ExplosionOrigin(shooter: shooter)
        )
        #expect(world.enchantments.count == 1)
        #expect(world.enchantments.first?.enchantment == Self.key(0x921))
        #expect(world.enchantments.first?.shooter == shooter)
        #expect(world.enchantments.first?.targets == [shooter, Self.npc])
        #expect(report.enchanted == [shooter, Self.npc])
        #expect(world.damage.isEmpty)
    }

    @Test func aCloseBlastSwapsInTheFixedModifierAtFullStrength() throws {
        let world = FakeExplosionWorld()
        let runtime = try Self.runtime(world: world)
        runtime.imageSpaceSwap = ExplosionImageSpaceSwap(modifier: Self.key(0x9FF))
        let spec = try #require(runtime.spec(for: Self.key(0x900)))
        // Radius 200: at 80 units the power is 0.84, above 0.75.
        world.viewer = SIMD3(80, 0, 60)
        #expect(runtime.detonate(spec, at: SIMD3(0, 0, 60), cause: .debug).swapApplied)
        #expect(world.modifiers.last?.0 == Self.key(0x9FF))
        #expect(world.modifiers.last?.1 == 1)
        // At 100 units the power is exactly 0.75, which is not above it.
        world.viewer = SIMD3(100, 0, 60)
        #expect(!runtime.detonate(spec, at: SIMD3(0, 0, 60), cause: .debug).swapApplied)
        var ignoring = spec
        ignoring.ignoresImageSpaceSwap = true
        world.viewer = SIMD3(10, 0, 60)
        #expect(!runtime.detonate(ignoring, at: SIMD3(0, 0, 60), cause: .debug).swapApplied)
    }

    @Test func aDebrisPlacementThrowsPiecesThatFallAndExpire() throws {
        let world = FakeExplosionWorld()
        let runtime = try Self.runtime(world: world)
        let spec = try #require(runtime.spec(for: Self.key(0x910)))
        let report = runtime.detonate(spec, at: .zero, cause: .debug)
        #expect(report.debrisThrown == DebrisSelection.pieceCount)
        let startZ = runtime.debris.map(\.velocity.z)
        runtime.advance(0.5)
        #expect(zip(runtime.debris.map(\.velocity.z), startZ).allSatisfy { $0 < $1 })
        runtime.advance(DebrisSelection.lifetime)
        #expect(runtime.debris.isEmpty)
        withExtendedLifetime(world) {}
    }

    @Test func debrisSelectionIsSeededAndWeighted() throws {
        let models = try Self.records().debris.records.first?.record.models ?? []
        let first = DebrisSelection.pick(models, count: 200, seed: 7)
        #expect(first == DebrisSelection.pick(models, count: 200, seed: 7))
        let heavy = first.filter { $0.path == "rock01.nif" }.count
        #expect(heavy > 100 && heavy < 180)
    }

    @Test func aTimedProjectileDetonatesInTheAir() throws {
        let world = FakeProjectileWorld()
        let runtime = ProjectileRuntime(settings: .synthetic, world: world)
        let blast = FakeExplosionWorld()
        let explosions = try Self.runtime(world: blast)
        runtime.explosions = explosions
        var profile = ProjectileProfile(
            speed: 1000,
            gravityFactor: 0,
            range: 4000,
            collisionRadius: 2
        )
        profile.explosion = FormID(0x900)
        profile.explosionTimer = 0.5
        _ = runtime.fire(Self.shot(profile))
        Self.advance(runtime, seconds: 1)
        #expect(explosions.detonationTotal == 1)
        #expect(runtime.live.isEmpty)
        withExtendedLifetime(blast) {}
    }

    @Test func aProximityProjectileDetonatesNearATarget() throws {
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: Self.npc, feet: SIMD3(500, 0, 0))]
        let runtime = ProjectileRuntime(settings: .synthetic, world: world)
        let blast = FakeExplosionWorld()
        blast.targets = world.targets
        let explosions = try Self.runtime(world: blast)
        runtime.explosions = explosions
        var profile = ProjectileProfile(
            speed: 1000,
            gravityFactor: 0,
            range: 4000,
            collisionRadius: 2
        )
        profile.explosion = FormID(0x900)
        profile.explosionProximity = 100
        _ = runtime.fire(Self.shot(profile))
        Self.advance(runtime, seconds: 1)
        #expect(explosions.detonationTotal == 1)
        let position = try #require(explosions.reports.first?.position)
        #expect(position.x <= 500)
        #expect(blast.damage[Self.npc] != nil)
    }

    /// A slow shot with a 100 unit proximity hangs still near the player. It notices the
    /// player 0.2 s before it goes off, and a failed roll keeps it from going off.
    private static func mineShot(world: FakeProjectileWorld) throws
        -> (ProjectileRuntime, ExplosionRuntime)
    {
        let runtime = ProjectileRuntime(settings: .synthetic, world: world)
        let explosions = try Self.runtime(world: FakeExplosionWorld())
        runtime.explosions = explosions
        var profile = ProjectileProfile(speed: 1, gravityFactor: 0, range: 4000, collisionRadius: 2)
        profile.explosion = FormID(0x900)
        profile.explosionProximity = 100
        world.shooter = ProjectileShooter(
            key: Self.npc, origin: .zero, aim: SIMD3(1, 0, 0), isFirstPerson: false,
            location: .exterior(CellCoordinate(x: 0, y: 0))
        )
        _ = runtime.fire(Self.shot(profile), from: world.shooter)
        return (runtime, explosions)
    }

    @Test func aMineOutdoorsReachesFartherAndBurnsAShortFuse() throws {
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: .player, feet: SIMD3(150, 0, 0))]
        let (runtime, explosions) = try Self.mineShot(world: world)
        Self.advance(runtime, seconds: 0.5)
        #expect(explosions.detonationTotal == 0)

        world.outdoors = true
        _ = runtime.advance(by: 1.0 / 60)
        #expect(runtime.live.first?.fuse.isBurning == true)
        Self.advance(runtime, seconds: 0.1)
        #expect(explosions.detonationTotal == 0)
        Self.advance(runtime, seconds: 0.2)
        #expect(explosions.detonationTotal == 1)
    }

    @Test func aFailedRollLeavesTheMineForThePlayer() throws {
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: .player, feet: SIMD3(50, 0, 0))]
        world.playerRollPasses = false
        let (runtime, explosions) = try Self.mineShot(world: world)
        Self.advance(runtime, seconds: 1)
        #expect(explosions.detonationTotal == 0)
        #expect(world.playerRolls == 1)
        #expect(runtime.live.first?.fuse.ignoresPlayer == true)
    }

    private static func shot(_ profile: ProjectileProfile) -> ProjectileShot {
        ProjectileShot.arrow(
            profile: profile,
            damage: ArcheryDamage.resolve(bowDamage: 10, arrowDamage: 0, skill: 0),
            weapon: FormID(0x0001_397E),
            ammunition: FormID(0x0001_397D)
        )
    }

    private static func advance(_ runtime: ProjectileRuntime, seconds: Float) {
        var elapsed: Float = 0
        while elapsed < seconds {
            _ = runtime.advance(by: 1.0 / 60)
            elapsed += 1.0 / 60
        }
    }
}

struct ExplosionReadoutTests {
    @Test func theReadoutShowsTheLastBlastAndTheHazards() {
        let report = ExplosionReport(
            name: "Blast", cause: .debug, position: .zero, damaged: [.player: 12.5],
            soundsPlayed: 1,
            imageSpaceStrength: 0.5, hazardPlaced: true, debrisThrown: 0
        )
        let hazard = TrapHazardRow(
            name: "Fire", remainingLifetime: 4, lastHitTargets: 1, lastHitEffects: 1,
            position: SIMD3(10, 20, 30), tickCount: 3
        )
        let text = ExplosionReadout.text(for: ExplosionControlSnapshot(
            reports: [report], detonationTotal: 1, debrisCount: 0, skippedPlacements: 0,
            hazards: [hazard]
        ))
        #expect(text
            .contains("Last: Blast (debug), 1 hit for 12.5, 1 sounds, screen 0.5, hazard placed"))
        #expect(text.contains("Fire at 10 20 30, 4.0 s left, 3 ticks"))
    }
}
