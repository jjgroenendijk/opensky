// Training through the coordinator: the trainer is paid, the session counts, a
// refusal shows its notice. The cost rules are in `TrainingSettingsTests`.

@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionInterface
import Testing

@MainActor
struct TrainingTests {
    private static let block: Int32 = 9

    @Test func aSessionPaysTheTrainerAndCountsTowardTheCap() throws {
        let world = FakeProgressionWorld()
        world.trainer = TrainerOffer(
            trainer: .generated(4), name: "Njada", skill: Self.block, maximumLevel: 75
        )
        world.gold = 1000
        let coordinator = try ProgressionCoordinatorFixture.make(world: world)

        coordinator.trainWithNearestTrainer()

        #expect(world.paid == [200])
        #expect(coordinator.takeCommands().contains(.incrementStat("Training Sessions")))
        #expect(coordinator.leveling?.state.trainingSessions == 1)
        #expect(coordinator.lastActionText.contains("Njada trained Block"))
    }

    @Test func aRefusalShowsItsNoticeAndChargesNothing() throws {
        let world = FakeProgressionWorld()
        world.trainer = TrainerOffer(
            trainer: .generated(4), name: "Njada", skill: Self.block, maximumLevel: 75
        )
        world.gold = 10
        let coordinator = try ProgressionCoordinatorFixture.make(world: world)

        #expect(try coordinator.train(with: #require(world.trainer)) == .refused(.insufficientGold))
        #expect(coordinator.takeCommands() == [.showNotification("sInsufficientGoldToTrain")])
        #expect(world.paid.isEmpty)
        #expect(coordinator.leveling?.state.trainingSessions == 0)
    }

    @Test func noTrainerNearbySaysSo() throws {
        let world = FakeProgressionWorld()
        let coordinator = try ProgressionCoordinatorFixture.make(world: world)
        #expect(coordinator.trainWithNearestTrainer().text(training: .vanilla)
            .hasPrefix("No trainer nearby"))
    }

    @Test func aLevelUpResetsTheSessions() {
        let trained = PlayerProgressState().training().training()
        let leveled = trained.leveled(
            CharacterLevelOutcome(levelsGained: 1, level: 2, carriedExperience: 0)
        )
        #expect(trained.trainingSessions == 2)
        #expect(leveled.trainingSessions == 0)
    }
}
