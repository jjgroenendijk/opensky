// Who set a blast off and from where: the shooter takes no damage, the skill scales it,
// a wall shields an actor, destructible objects take damage, and an object is placed.

import Foundation
@testable import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
final class FakeOriginExplosionWorld: ExplosionWorld {
    var targets: [MeleeTarget] = []
    var objects: [MeleeTarget] = []
    var wallDistance: Float?
    var placementWorks = true
    private(set) var damage: [ReferenceKey: Float] = [:]
    private(set) var objectDamage: [ReferenceKey: Float] = [:]
    private(set) var sightLines: [(SIMD3<Float>, SIMD3<Float>)] = []
    private(set) var placed: [ExplosionObjectPlacement] = []

    func explosionTargets() -> [MeleeTarget] {
        targets
    }

    func explosionViewer() -> SIMD3<Float>? {
        nil
    }

    func applyExplosionDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        damage[target, default: 0] += amount
        return true
    }

    func playExplosionSound(_: ReferenceKey, at _: SIMD3<Float>) {}
    func startExplosionImageSpace(_: ReferenceKey, strength _: Float) {}
    func placeExplosionHazard(_: ReferenceKey, at _: SIMD3<Float>) -> Bool {
        true
    }

    func showExplosionModel(_: String, at _: SIMD3<Float>) {}

    func explosionObstruction(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Float? {
        sightLines.append((start, end))
        return wallDistance
    }

    func explosionObjects(within radius: Float, of center: SIMD3<Float>) -> [MeleeTarget] {
        objects.filter { simd_distance($0.feet, center) <= radius }
    }

    func applyDestructionDamage(_ amount: Float, to object: ReferenceKey) -> Bool {
        objectDamage[object, default: 0] += amount
        return true
    }

    func placeExplosionObject(_ placement: ExplosionObjectPlacement) -> Bool {
        placed.append(placement)
        return placementWorks
    }
}

@MainActor
struct ExplosionOriginTests {
    static let npc = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x700)
    static let barrel = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x710)

    private static func runtime(_ world: FakeOriginExplosionWorld) throws -> ExplosionRuntime {
        try ExplosionRuntime(
            records: ExplosionRuntimeTests.records(), itemPlugin: ExplosionRuntimeTests.plugin,
            world: world
        )
    }

    private static let blast = ExplosionSpec(name: "Blast", damage: 40, radius: 200)

    @Test func theShooterTakesNoDamageAndTheSkillScalesTheRest() throws {
        let world = FakeOriginExplosionWorld()
        world.targets = [
            MeleeTarget(key: .player, feet: .zero), MeleeTarget(key: Self.npc, feet: .zero)
        ]
        let runtime = try Self.runtime(world)
        let plain = runtime.detonate(Self.blast, at: .zero, cause: .projectile)
        let report = runtime.detonate(
            Self.blast, at: .zero, cause: .projectile,
            origin: ExplosionOrigin(shooter: .player, skill: 100)
        )
        #expect(report.damaged[.player] == nil)
        // Skill 100 scales the player's blast by 1.5.
        let scaled = (plain.damaged[Self.npc] ?? 0) * 1.5
        #expect(abs((report.damaged[Self.npc] ?? 0) - scaled) < 0.001)
    }

    @Test func aWorldThatCastsNoEnchantmentReportsNone() throws {
        let world = FakeOriginExplosionWorld()
        world.targets = [MeleeTarget(key: Self.npc, feet: .zero)]
        var spec = Self.blast
        spec.enchantment = Self.barrel
        let report = try Self.runtime(world).detonate(spec, at: .zero, cause: .debug)
        #expect(report.enchanted.isEmpty)
        #expect(report.damaged[Self.npc] != nil)
    }

    @Test func aWallShieldsAnActorUnlessTheBlastIgnoresLineOfSight() throws {
        let world = FakeOriginExplosionWorld()
        world.targets = [MeleeTarget(key: Self.npc, feet: SIMD3(100, 0, 0))]
        world.wallDistance = 30
        let runtime = try Self.runtime(world)
        let blocked = runtime.detonate(
            Self.blast, at: .zero, cause: .projectile,
            origin: ExplosionOrigin(direction: SIMD3(0, 0, 1))
        )
        #expect(blocked.shielded == [Self.npc])
        #expect(blocked.damaged.isEmpty)
        #expect(world.sightLines.first?.0 == SIMD3(0, 0, ExplosionSight.startOffset))

        var through = Self.blast
        through.ignoresLineOfSight = true
        #expect(runtime.detonate(through, at: .zero, cause: .projectile).damaged[Self.npc] != nil)
    }

    @Test func aBlastPointingDownIgnoresTheFloorRightBelowIt() {
        let down = SIMD3<Float>(0, 0, -1)
        #expect(!ExplosionSight.blocks(hitDistance: 1, direction: down))
        #expect(ExplosionSight.blocks(hitDistance: 10, direction: down))
        #expect(ExplosionSight.blocks(hitDistance: 1, direction: SIMD3(1, 0, 0)))
        #expect(!ExplosionSight.blocks(hitDistance: nil, direction: down))
        #expect(ExplosionSight.start(center: .zero, direction: nil) == .zero)
    }

    @Test func theSkillScaleFavoursNPCs() {
        #expect(ExplosionSkill.scale(skill: 50, isPlayer: true) == 1.25)
        #expect(ExplosionSkill.scale(skill: 50, isPlayer: false) == 2)
        #expect(ExplosionSkill.scale(skill: nil, isPlayer: true) == 1)
        #expect(ExplosionSkill.scale(skill: -10, isPlayer: false) == 1)
    }

    @Test func destructibleObjectsInTheRadiusTakeDamage() throws {
        let world = FakeOriginExplosionWorld()
        let far = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x711)
        world.objects = [
            MeleeTarget(key: Self.barrel, feet: .zero),
            MeleeTarget(key: far, feet: SIMD3(900, 0, 0))
        ]
        let runtime = try Self.runtime(world)
        let report = runtime.detonate(Self.blast, at: .zero, cause: .spell)
        #expect(report.objectsDamaged == [Self.barrel: 40])
        #expect(world.objectDamage[far] == nil)
    }

    @Test func anOtherPlacementBecomesANewReference() throws {
        let world = FakeOriginExplosionWorld()
        let runtime = try Self.runtime(world)
        let base = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x720)
        let spec = ExplosionSpec(name: "Spawn", placement: .other(base, type: "ACTI"))
        let location = CellSceneLocation.exterior(CellCoordinate(x: 1, y: 2))
        let origin = ExplosionOrigin(
            shooter: .player, direction: SIMD3(1, 0, 0), location: location, owner: Self.barrel
        )
        #expect(runtime.detonate(spec, at: .zero, cause: .spell, origin: origin).objectPlaced)
        #expect(world.placed.first?.base == base)
        #expect(world.placed.first?.location == location)
        #expect(world.placed.first?.ownerSource == Self.barrel)
        let heading = world.placed.first?.rotation.z ?? 0
        #expect(abs(heading - .pi / 2) < 1e-5)

        world.placementWorks = false
        #expect(!runtime.detonate(spec, at: .zero, cause: .spell).objectPlaced)
        #expect(runtime.skippedPlacements == 1)
    }

    @Test func aPlacementWithoutAnOwnerTakesTheShootersCrimeOwner() throws {
        let world = FakeOriginExplosionWorld()
        let runtime = try Self.runtime(world)
        let base = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x720)
        let spec = ExplosionSpec(name: "Spawn", placement: .other(base, type: "ACTI"))
        _ = runtime.detonate(
            spec,
            at: .zero,
            cause: .spell,
            origin: ExplosionOrigin(shooter: Self.npc)
        )
        #expect(world.placed.first?.ownerSource == Self.npc)
    }

    @Test func aPlacedObjectFacesAlongTheBlast() {
        #expect(ExplosionObjectPlacement.rotation(facing: nil) == .zero)
        #expect(ExplosionObjectPlacement.rotation(facing: .zero) == .zero)
        let north = ExplosionObjectPlacement.rotation(facing: SIMD3(0, 5, 0))
        #expect(abs(north.x) < 1e-6 && abs(north.z) < 1e-6)
        let up = ExplosionObjectPlacement.rotation(facing: SIMD3(0, 0, 1))
        #expect(abs(up.x + .pi / 2) < 1e-5)
    }
}
