// The disease roll of a creature's hit: the pure rule, and a landed NPC blow.

@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
@testable import OpenSkyMagicInterface
import Testing

@MainActor
struct DiseaseContractionTests {
    private static let skeever = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x900)
    private static let target = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x901)
    private static let ataxia = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x20)

    /// The chance is 100 minus the whole resistance, capped at 100, against a 0 to 99 roll.
    @Test
    func chanceFollowsTheResistance() {
        #expect(DiseaseContraction.contracts(resist: 0, roll: 99))
        #expect(DiseaseContraction.contracts(resist: 50.9, roll: 49))
        #expect(!DiseaseContraction.contracts(resist: 50.9, roll: 50))
        #expect(!DiseaseContraction.contracts(resist: 100, roll: 0))
        #expect(!DiseaseContraction.contracts(resist: 250, roll: 0))
        #expect(DiseaseContraction.contracts(resist: -20, roll: 99))
        #expect(!DiseaseContraction.contracts(resist: nil, roll: 0))
        #expect(DiseaseContraction.resistIndex != nil)
    }

    @Test
    func aLandedBlowPassesTheAttackersDisease() {
        let world = FakeCombatWorld()
        world.attackDiseases[Self.skeever] = Self.ataxia
        world.diseaseResists[Self.target] = 0
        let landing = CombatNPCBlowLanding(
            world: world, settings: .synthetic, skillUses: .vanilla, staggers: .vanilla
        )
        var random = ConditionRandom(seed: 7)
        _ = landing.land(from: Self.skeever, weapon: .unarmed, to: Self.target, random: &random)
        #expect(world.contractedDiseases.map(\.disease) == [Self.ataxia])
        #expect(world.contractedDiseases.map(\.target) == [Self.target])
    }

    @Test
    func fullResistanceNeverContracts() {
        let world = FakeCombatWorld()
        world.attackDiseases[Self.skeever] = Self.ataxia
        world.diseaseResists[Self.target] = 100
        let landing = CombatNPCBlowLanding(
            world: world, settings: .synthetic, skillUses: .vanilla, staggers: .vanilla
        )
        var random = ConditionRandom(seed: 7)
        for _ in 0 ..< 20 {
            _ = landing.land(from: Self.skeever, weapon: .unarmed, to: Self.target, random: &random)
        }
        #expect(world.contractedDiseases.isEmpty)
    }
}
