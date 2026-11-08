// Legendary skills and the Dragonborn altar over the fixture tree: who may reset a
// tree, what it refunds, and what the skills menu reads back.

import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionInterface
import Testing

@MainActor
struct ProgressionPerkResetTests {
    private let damageRank1 = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1)
    private let damageRank2 = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank2)
    private let oneHanded = PerkRuntimeFixture.oneHandedIndex
    /// Held here, because the coordinators keep their world weakly.
    private let world = FakeProgressionWorld()

    private func coordinator(skillLevel: Float) throws -> ProgressionCoordinator {
        try ProgressionCoordinatorFixture.make(world: world, skillLevel: skillLevel)
    }

    @Test func aSkillBelowOneHundredIsNotMadeLegendary() throws {
        let coordinator = try coordinator(skillLevel: 15)

        #expect(coordinator.makeSkillLegendary(oneHanded) == .failure(.belowLegendaryLevel(15)))
        #expect(coordinator.makeSkillLegendary(3) == .failure(.notASkill))
    }

    @Test func aLegendarySkillRefundsEveryRankAndCountsOnce() throws {
        let coordinator = try coordinator(skillLevel: 100)
        coordinator.perks.add(damageRank1, to: .player)
        coordinator.perks.add(damageRank2, to: .player)

        let report = try coordinator.makeSkillLegendary(oneHanded).get()

        #expect(report.refundedPoints == 2)
        #expect(report.perkPoints == 2)
        #expect(report.legendaryCount == 1)
        #expect(coordinator.perks.ownership(of: .player)?.isEmpty == true)
        #expect(coordinator.skillsMenuSkills.first { $0.index == oneHanded }?.legendaryCount == 1)
    }

    @Test func theAltarRefusesAnEmptyTreeAndRefundsAFullOne() throws {
        let coordinator = try coordinator(skillLevel: 15)
        #expect(coordinator.resetPerkTree(oneHanded) == .failure(.noPerksInTree))

        coordinator.perks.add(damageRank1, to: .player)
        let report = try coordinator.resetPerkTree(oneHanded).get()

        #expect(report.refundedPoints == 1)
        #expect(report.legendaryCount == 0)
        #expect(coordinator.ownedTreePerks(ofSkill: oneHanded).isEmpty)
    }

    @Test func theSkillsMenuBuysTheNextRankOfABox() throws {
        let coordinator = try coordinator(skillLevel: 100)
        _ = coordinator.modifyPerkPoints(by: 2)
        let box = try #require(coordinator.skillsMenuPerks(forSkill: oneHanded).first {
            $0.rankCount == 2
        })
        #expect(box.refusal == nil)

        #expect(coordinator
            .skillsMenuBuyPerk(node: box.node, forSkill: oneHanded) == .done("Perk added."))
        #expect(coordinator
            .skillsMenuBuyPerk(node: box.node, forSkill: oneHanded) == .done("Perk added."))

        let owned = try #require(coordinator.skillsMenuPerks(forSkill: oneHanded).first {
            $0.node == box.node
        })
        #expect(owned.ownedRank == 2)
        #expect(owned.refusal == "owned")
        #expect(coordinator.skillsMenuPlayer.perkPoints == 0)
    }
}
