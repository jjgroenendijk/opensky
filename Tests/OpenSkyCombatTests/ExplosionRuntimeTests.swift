// The explosion runtime over a synthetic EXPL plugin: falloff damage, sounds,
// the image-space strength, hazard and debris placement, seeded debris, and a
// projectile's timer and proximity detonation.

import Foundation
@testable import OpenSkyCombat
import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
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
}

@MainActor
struct ExplosionRuntimeTests {
    private typealias Fixture = ESMFixture
    static let plugin = "Effects.esm"
    static let npc = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x700)

    static func explosion(_ formID: UInt32, placed: UInt32, sound: UInt32 = 0) -> Data {
        let links = Fixture.u32(0, sound, 0, 0, placed, 0)
        return Fixture.recordBytes("EXPL", formID: formID, fields: [
            ("EDID", Fixture.zstring("TestBlast\(formID)")),
            ("MODL", Fixture.zstring("fx/blast.nif")),
            ("MNAM", Fixture.u32(0x950)),
            ("DATA", links + Fixture.f32(400, 50, 200, 1000))
        ])
    }

    static func records() throws -> EffectRecordStore {
        let file = try Fixture.plugin(records: [
            explosion(0x900, placed: 0x901, sound: 0x902),
            explosion(0x910, placed: 0x911),
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
        let runtime = ExplosionRuntime()
        runtime.records = try records()
        runtime.itemPlugin = plugin
        runtime.world = world
        return runtime
    }

    @Test func damageFallsOffLinearlyToTheEdge() {
        #expect(ExplosionFalloff.damage(50, radius: 200, distance: 0) == 50)
        #expect(ExplosionFalloff.damage(50, radius: 200, distance: 100) == 25)
        #expect(ExplosionFalloff.damage(50, radius: 200, distance: 250) == 0)
        #expect(ExplosionFalloff.damage(50, radius: 0, distance: 0) == 50)
        #expect(ExplosionFalloff.imageSpaceStrength(radius: 0, distance: 900) == 1)
        #expect(ExplosionFalloff.imageSpaceStrength(radius: 1000, distance: 250) == 0.75)
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
        #expect(world.damage == [Self.npc: 25])
        #expect(world.sounds == [Self.key(0x902)])
        #expect(world.hazards == [Self.key(0x901)])
        #expect(world.models == ["fx/blast.nif"])
        #expect(world.modifiers.first?.1 == 0.75)
        #expect(report.hazardPlaced)
        #expect(runtime.detonationTotal == 1)
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
        let runtime = ProjectileRuntime(settings: .synthetic)
        let world = FakeProjectileWorld()
        runtime.attach(world: world)
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
        let runtime = ProjectileRuntime(settings: .synthetic)
        let world = FakeProjectileWorld()
        world.targets = [MeleeTarget(key: Self.npc, feet: SIMD3(500, 0, 0))]
        runtime.attach(world: world)
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
        #expect(position.x < 450)
        #expect(blast.damage[Self.npc] != nil)
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
