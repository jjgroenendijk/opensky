// A hit through the body part it struck: the ranged damage multiplier, limb damage,
// and the blood sprayed on a nearby surface. Rules: docs/formats/body-parts.md.

import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyPhysics
import OpenSkyRenderCore
import simd
import Testing

@MainActor
struct BodyPartHitTests {
    private static let target = ReferenceKey.generated(1)
    private static let bloodSet = FormID(0x200)

    private static func coordinator() throws -> (CombatCoordinator, FakeCoordinatorWorld) {
        let world = FakeCoordinatorWorld()
        world.healths[target] = (100, 100)
        var data = CombatSessionData(combat: .synthetic, archery: .synthetic)
        data.impacts = try impacts()
        return (CombatCoordinator(world: world, data: data), world)
    }

    /// One blood set whose only impact leaves a decal. Like the vanilla blood spray
    /// impact, it has no sound.
    private static func impacts() throws -> MeleeImpactResolver {
        let impact = try Impact(record: ESMFixture.record("IPCT", formID: 0x300, fields: []))
        let dataSet = ImpactDataSet(
            formID: bloodSet, editorID: nil,
            entries: [ImpactDataSet.Entry(material: FormID(1), impact: FormID(0x300))]
        )
        return MeleeImpactResolver(footsteps: FootstepStore(
            sets: [], footsteps: [], impactDataSets: [dataSet], impacts: [impact]
        ))
    }

    @Test func thePickTakesTheNearestPartAndSkipsAPartNoHitNotes() {
        let parts = [
            BodyPartPlacement(partType: 0, position: SIMD3(0, 0, 60), toHitChance: 100),
            BodyPartPlacement(partType: 1, position: SIMD3(0, 0, 120), toHitChance: 0)
        ]
        #expect(BodyPartHitRules.struckPart(parts, at: SIMD3(0, 0, 70))?.partType == 0)
        #expect(BodyPartHitRules.struckPart(parts, at: SIMD3(0, 0, 115)) == nil)
        #expect(BodyPartHitRules.struckPart([], at: .zero) == nil)
    }

    @Test func theLimbTakesItsShareOfTheHit() {
        let part = StruckBodyPart(partType: 1, node: "NPC Head", healthPercent: 5, actorValue: 25)
        // docs/formats/body-parts.md: base Health 200, health percent 5, damage 20 gives 200.
        #expect(BodyPartHitRules.limbDamage(
            20, part: part, baseHealth: 200, playerMultiplier: nil
        ) == 200)
        #expect(BodyPartHitRules.limbDamage(20, part: part, baseHealth: 200, playerMultiplier: 0.5)
            == 100)
        #expect(BodyPartHitRules.limbDamage(20, part: part, baseHealth: 0, playerMultiplier: nil)
            == 20)
        var none = part
        none.healthPercent = 0
        #expect(BodyPartHitRules.limbDamage(20, part: none, baseHealth: 200, playerMultiplier: nil)
            == 0)
    }

    @Test func onlyARangedHitTakesThePartMultiplierAndItNeverLowers() {
        var part = StruckBodyPart(partType: 1, node: "NPC Head", damageMultiplier: 3)
        #expect(BodyPartHitRules.damageMultiplier(of: part, kind: .ranged) == 3)
        #expect(BodyPartHitRules.damageMultiplier(of: part, kind: .melee) == 1)
        part.damageMultiplier = 0.5
        #expect(BodyPartHitRules.damageMultiplier(of: part, kind: .ranged) == 1)
        #expect(BodyPartHitRules.damageMultiplier(of: nil, kind: .ranged) == 1)
    }

    @Test func anArrowOnTheHeadHitsHarderAndHurtsTheLimb() throws {
        let (coordinator, world) = try Self.coordinator()
        world.values[Self.target] = [BodyPartHitTestsValues.health: 200]
        world.struckParts[Self.target] = StruckBodyPart(
            partType: 1, node: "NPC Head", damageMultiplier: 2, healthPercent: 5, actorValue: 25
        )
        coordinator.shared.damage.applyHealthDamage(
            10, to: Self.target, attacker: nil, kind: .ranged, at: SIMD3(0, 0, 120)
        )
        #expect(world.damage.last?.amount == 20)
        #expect(world.limbDamage.map(\.index) == [25])
        #expect(world.limbDamage.first?.amount == 200)
        coordinator.shared.damage.applyHealthDamage(10, to: Self.target, attacker: nil)
        #expect(world.limbDamage.count == 1, "a hit with no attack behind it finds no part")
    }

    @Test func aSwingAndAnArrowCarryTheirContactPoint() throws {
        let (coordinator, world) = try Self.coordinator()
        world.struckParts[Self.target] = StruckBodyPart(partType: 0, node: "NPC Spine")
        #expect(coordinator.meleeWorld.applyMeleeDamage(4, to: Self.target, at: SIMD3(0, 0, 60)))
        #expect(coordinator.projectileWorld.applyProjectileDamage(
            4, to: Self.target, from: .generated(7), at: SIMD3(0, 0, 60)
        ))
        #expect(world.damage.count == 2)
    }

    @Test func theBloodRayRunsAwayFromTheBlowAndDown() throws {
        let ray = try #require(BodyPartHitRules.bloodRay(
            hitDirection: SIMD3(10, 0, 0), jitter: .zero
        ))
        #expect(abs(ray.x - 2 / sqrtf(5)) < 0.001)
        #expect(ray.z < 0)
        #expect(BodyPartHitRules.bloodRay(hitDirection: .zero, jitter: .zero) == nil)
    }

    @Test func aBloodSetSpraysOneDecalOnTheSurfaceTheRayMeets() throws {
        let (coordinator, world) = try Self.coordinator()
        world.struckParts[Self.target] = StruckBodyPart(
            partType: 0, node: "NPC Spine", position: SIMD3(100, 0, 60),
            bloodImpactDataSet: Self.bloodSet
        )
        world.sweepHit = ShapeSweepHit(
            reference: FormID(9), distance: 50, position: SIMD3(140, 0, 0),
            normal: SIMD3(0, 0, 1), startsOverlapping: false, material: nil
        )
        for _ in 0 ..< 8 {
            coordinator.shared.damage.applyHealthDamage(
                1, to: Self.target, attacker: .player, kind: .melee
            )
        }
        let decals = coordinator.shared.pendingCommands.filter {
            if case .placeBloodDecal = $0 {
                return true
            }
            return false
        }
        #expect(!decals.isEmpty, "a 0.75 chance lands in eight hits")
        #expect(world.sweeps.count == decals.count, "each ray that runs meets the floor")
        #expect(world.sweeps.allSatisfy { $0.maximumDistance == 512 })
        #expect(world.sweeps.allSatisfy { $0.direction.x > 0 })
    }

    @Test func theNearerOfTheLandAndAPlacedSurfaceTakesTheBlood() throws {
        let (coordinator, world) = try Self.coordinator()
        world.struckParts[Self.target] = StruckBodyPart(
            partType: 0, node: "NPC Spine", position: SIMD3(100, 0, 60),
            bloodImpactDataSet: Self.bloodSet
        )
        world.sweepHit = ShapeSweepHit(
            reference: FormID(9), distance: 300, position: SIMD3(400, 0, 0),
            normal: SIMD3(1, 0, 0), startsOverlapping: false, material: nil
        )
        world.groundHitResult = TerrainRayHit(
            position: SIMD3(130, 0, 0), normal: SIMD3(0, 0, 1), distance: 40
        )
        for _ in 0 ..< 8 {
            coordinator.shared.damage.applyHealthDamage(
                1, to: Self.target, attacker: .player, kind: .melee
            )
        }
        let places = coordinator.shared.pendingCommands.compactMap { command -> SIMD3<Float>? in
            guard case let .placeBloodDecal(_, at: position, normal: _) = command
            else { return nil }
            return position
        }
        #expect(!places.isEmpty)
        #expect(places.allSatisfy { $0 == SIMD3(130, 0, 0) })
    }
}

private enum BodyPartHitTestsValues {
    static let health: Int32 = 24
}
