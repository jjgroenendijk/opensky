// The progression shell over the fixture tree: the panel's selections, the
// perk-point spend and its refusals, and the world reads it makes.

import FeaturesTesting
import OpenSkyActorsInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct ProgressionCoordinatorTests {
    private static let damageNode: UInt32 = 1
    private let damageRank1 = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1)
    private let oneHanded = PerkRuntimeFixture.oneHandedIndex

    private func coordinator(world: FakeProgressionWorld) throws -> ProgressionCoordinator {
        let store = WorldStateStore()
        let index = try PerkRuntimeFixture.index()
        let information = PerkRuntimeFixture.informationStore(index: index)
        let perkStore = PerkRuntimeFixture.perkStore(index: index)
        let perks = PerkCoordinator()
        perks.attach(world: world)
        perks.wire(
            PerkRuntime(store: store, perks: perkStore, conditionRegistry: .empty),
            baselines: nil,
            pluginName: PerkRuntimeFixture.pluginName
        )
        let coordinator = ProgressionCoordinator(perks: perks)
        coordinator.attach(world: world)
        let values = FixedActorValues(store: store, indexedValue: 15)
        coordinator.wireSkills(values: values, information: information)
        coordinator.wireLeveling(values: values, perkStore: perkStore, information: information)
        return coordinator
    }

    // MARK: - Without game data

    @Test func withoutGameDataThePanelIsUnavailable() {
        let coordinator = ProgressionCoordinator(perks: PerkCoordinator())

        #expect(coordinator.snapshot == .unavailable)
        #expect(coordinator.reportSkillUse(SkillUseEvent(
            actor: .player,
            action: .blockedBlow,
            amount: 10
        )) == 0)
        #expect(coordinator.modifyPerkPoints(by: 1) == nil)
        #expect(
            coordinator.changePerkPoints(by: 1) == "Progression unavailable: no game data loaded."
        )
        #expect(coordinator.spendPerkPoint(on: damageRank1) == .failure(.noPerkPoints))
        #expect(coordinator.chooseAttribute(.health) == .failure(.noAttributePickOwed))
    }

    // MARK: - Selection

    @Test func wiringSelectsTheFirstBoxOfTheSelectedTree() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)

        #expect(coordinator.skillSelection == oneHanded)
        #expect(coordinator.nodeSelection == coordinator.perkTreeNodes(forSkill: oneHanded)[0].node)
    }

    @Test func aNonSkillIndexIsIgnored() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)

        coordinator.selectSkill(24)

        #expect(coordinator.skillSelection == oneHanded)
    }

    @Test func changingSkillMovesTheBoxToTheNewTree() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        coordinator.nodeSelection = Self.damageNode

        coordinator.selectSkill(oneHanded + 1)

        #expect(coordinator.skillSelection == oneHanded + 1)
        #expect(coordinator.nodeSelection == 0)
    }

    // MARK: - Perk points

    @Test func aSpendWithoutPointsIsRefused() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        coordinator.nodeSelection = Self.damageNode

        #expect(coordinator.spendPointOnSelectedPerk() == "No perk points to spend.")
        #expect(coordinator.perks.ownership(of: .player)?.isEmpty == true)
    }

    @Test func aSpendGrantsThePerkAndTakesThePoint() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        coordinator.nodeSelection = Self.damageNode
        #expect(coordinator.changePerkPoints(by: 1) == "Changed perk points by 1: 1 unspent.")

        #expect(coordinator.spendPerkPoint(on: damageRank1).map(\.perkPoints) == .success(0))
        #expect(coordinator.perks.ownership(of: .player) == [damageRank1])
        #expect(world.reconciled == [.player])
    }

    @Test func anOwnedPerkIsRefusedAndKeepsThePoint() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        coordinator.perks.add(damageRank1, to: .player)
        _ = coordinator.modifyPerkPoints(by: 1)

        guard case .failure(.perkRefused) = coordinator.spendPerkPoint(on: damageRank1) else {
            Issue.record("an owned perk was bought again")
            return
        }
        #expect(coordinator.modifyPerkPoints(by: 0) == 1)
    }

    @Test func grantAndRevokeReportWhatChanged() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        coordinator.nodeSelection = Self.damageNode

        #expect(coordinator.grantSelectedPerk() == "Granted Damage Rank 1.")
        #expect(coordinator.grantSelectedPerk() == "Damage Rank 1 was already owned.")
        #expect(coordinator.revokeSelectedPerk() == "Removed Damage Rank 1.")
        #expect(coordinator.revokeSelectedPerk() == "Damage Rank 1 was not owned.")
    }

    @Test func theTreeEntryGrantsNoPerk() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        coordinator.nodeSelection = coordinator.perkTreeNodes(forSkill: oneHanded)[0].node

        #expect(coordinator.grantSelectedPerk() == "This box grants no perk.")
    }

    // MARK: - World reads

    @Test func theInspectionPrintsConditionsThroughTheWorld() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)

        let inspection = coordinator.perkInspection(node: Self.damageNode, forSkill: oneHanded)

        #expect(inspection?.name == "Damage Rank 1")
        #expect(inspection?.conditions.allSatisfy { $0.hasPrefix("function ") } == true)
    }

    @Test func aSkillUseAsksTheWorldWhatTheTargetWears() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        let target = ReferenceKey.plugin(name: "perkruntime.esm", objectID: 0x0900)

        _ = coordinator.skills?.wornArmor(target)

        #expect(world.wornArmorReads == [target])
    }
}
