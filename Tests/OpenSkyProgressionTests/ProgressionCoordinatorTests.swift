// The progression shell over the fixture tree: the panel's selections, the
// perk-point spend and its refusals, and the world reads it makes.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionInterface
import Testing

@MainActor
struct ProgressionCoordinatorTests {
    private static let damageNode: UInt32 = 1
    private let damageRank1 = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1)
    private let oneHanded = PerkRuntimeFixture.oneHandedIndex

    private func coordinator(world: FakeProgressionWorld) throws -> ProgressionCoordinator {
        try ProgressionCoordinatorFixture.make(world: world)
    }

    // MARK: - Without game data

    @Test func withoutGameDataThePanelIsUnavailable() {
        let coordinator = ProgressionCoordinator(
            perks: PerkCoordinator(world: FakeProgressionWorld()), world: FakeProgressionWorld()
        )

        #expect(coordinator.snapshot == .unavailable)
        #expect(coordinator.reportSkillUse(SkillUseEvent(
            actor: .player,
            action: .blockedBlow,
            amount: 10
        )) == 0)
        #expect(coordinator.modifyPerkPoints(by: 1) == nil)
        #expect(
            coordinator.changePerkPoints(by: 1).text(training: .vanilla)
                == "Progression unavailable: no game data loaded."
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

        #expect(coordinator.spendPointOnSelectedPerk()
            .text(training: .vanilla) == "No perk points to spend.")
        #expect(coordinator.perks.ownership(of: .player)?.isEmpty == true)
    }

    @Test func aSpendGrantsThePerkAndTakesThePoint() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        coordinator.nodeSelection = Self.damageNode
        #expect(coordinator.changePerkPoints(by: 1)
            .text(training: .vanilla) == "Changed perk points by 1: 1 unspent.")

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

        #expect(coordinator.grantSelectedPerk()
            .text(training: .vanilla) == "Granted Damage Rank 1.")
        #expect(coordinator.grantSelectedPerk()
            .text(training: .vanilla) == "Damage Rank 1 was already owned.")
        #expect(coordinator.revokeSelectedPerk()
            .text(training: .vanilla) == "Removed Damage Rank 1.")
        #expect(coordinator.revokeSelectedPerk()
            .text(training: .vanilla) == "Damage Rank 1 was not owned.")
    }

    @Test func theTreeEntryGrantsNoPerk() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        coordinator.nodeSelection = coordinator.perkTreeNodes(forSkill: oneHanded)[0].node

        #expect(coordinator.grantSelectedPerk()
            .text(training: .vanilla) == "This box grants no perk.")
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

    // MARK: - Story events

    @Test func aSkillPointAndALevelUpFireTheirStoryEvents() throws {
        let coordinator = try coordinator(world: FakeProgressionWorld())
        let recorder = StoryEventRecorder()
        coordinator.storyEvents = recorder

        #expect(coordinator.incrementSkill(oneHanded))
        coordinator.awardCharacterExperience(100_000)

        #expect(recorder.events("SKIL").map(\.value1) == [Float(oneHanded)])
        let level = try #require(coordinator.leveling?.level)
        #expect(level > 1)
        #expect(recorder.events("LEVL").last?.value1 == Float(level))
    }

    @Test func aSkillPointAndALevelUpShowTheirNotices() throws {
        let world = FakeProgressionWorld()
        let coordinator = try coordinator(world: world)
        coordinator.texts.skillIncreased = "%s rose to %i"

        #expect(coordinator.incrementSkill(oneHanded))
        coordinator.awardCharacterExperience(100_000)

        let name = coordinator.skillName(oneHanded)
        let commands = coordinator.takeCommands()
        guard case let .showNotification(first) = commands.first else {
            Issue.record("no skill notice")
            return
        }
        #expect(first.hasPrefix("\(name) rose to "))
        #expect(commands.last == .showNotification(ProgressionTexts.vanilla.levelUpAvailable))
    }
}
