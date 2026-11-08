// Training cost and refusals: the UESP formulas, the five-per-level cap, the
// trainer's limit, and the gold check. UESP "Skyrim:Trainers".

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct TrainingSettingsTests {
    /// Sums one-session costs, as UESP's `n(...)` formulas do.
    private static func total(from level: Int, sessions: Int) -> Int {
        (0 ..< sessions).reduce(0) { $0 + TrainingSettings.vanilla.cost(skillLevel: level + $1) }
    }

    @Test func oneSessionMatchesEachUESPFormula() {
        // n(10b + 5n + 45), n(30b + 15n + 35), n(50b + 25n + 25) with n = 1.
        #expect(TrainingSettings.vanilla.cost(skillLevel: 20) == 250)
        #expect(TrainingSettings.vanilla.cost(skillLevel: 60) == 30 * 60 + 50)
        #expect(TrainingSettings.vanilla.cost(skillLevel: 80) == 50 * 80 + 50)
        // UESP's example: 20 to 50 costs 30(10 * 20 + 5 * 30 + 45) = 11850.
        #expect(Self.total(from: 20, sessions: 30) == 11850)
    }

    @Test func refusalsFollowTheTrainerTheCapAndTheGold() {
        let settings = TrainingSettings.vanilla
        let refusal = { (level: Int, sessions: Int, gold: Int) in
            settings.refusal(
                skillLevel: level, trainerMaximum: 50, sessionsThisLevel: sessions, gold: gold
            )
        }
        #expect(refusal(50, 0, 10000) == .trainerLimit)
        #expect(refusal(20, 5, 10000) == .levelUpFirst)
        #expect(refusal(20, 0, 249) == .insufficientGold)
        #expect(refusal(20, 4, 250) == nil)
    }

    @Test func settingsComeFromTheLoadOrder() throws {
        let store = try GameSettingFixture.store([
            "fTrainingMultCost": .float(20),
            "iTrainingMasterCost": .integer(2),
            "sCanNotTrainHigher": .text("No higher")
        ])
        let settings = TrainingSettings.resolve(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        #expect(settings.cost(skillLevel: 10) == 250)
        #expect(settings.cost(skillLevel: 80) == 20 * 2 * 80 + 50)
        #expect(settings.text(for: .trainerLimit) == "No higher")
        #expect(settings.text(for: .levelUpFirst) == "sCanNotTrainAnymore")
    }
}
