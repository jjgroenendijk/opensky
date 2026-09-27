// Character leveling at runtime (issue #499, roadmap item 20.6): banking
// experience, crossing thresholds, the attribute pick and the perk-point pool.
//
// Baselines are synthetic for the reason `SkillAdvancementRuntimeTests` uses
// synthetic ones: what is under test is the relationship between an award, a
// threshold and a stored component, not where the settings came from.

import Foundation
@testable import opensky
import Testing

@MainActor
struct PlayerLevelRuntimeTests {
    private static let health = ActorValueIdentity.index(of: .health)
    private static let stamina = ActorValueIdentity.index(of: .stamina)

    private func runtime(
        levelSource: PlayerLevelSource = PlayerLevelSource()
    ) -> (PlayerLevelRuntime, WorldStateStore) {
        let store = WorldStateStore()
        let values = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 100),
                    regenPercentPerSecond: .zero,
                    general: [ActorValueIdentity.carryWeightIndex: 300]
                ),
                playerLevel: levelSource
            )
        )
        return (PlayerLevelRuntime(values: values), store)
    }

    /// A fresh session is level 1 with nothing stored: the component only
    /// appears once something happens.
    @Test func aFreshSessionStoresNothing() {
        let (runtime, store) = self.runtime()

        #expect(runtime.level == 1)
        #expect(runtime.perkPoints == 0)
        #expect(runtime.experienceForNextLevel == 100)
        #expect(store.component(PlayerProgressState.self, for: .player) == nil)
    }

    /// Experience short of the threshold banks and levels nothing.
    @Test func experienceBelowTheThresholdBanks() {
        let (runtime, _) = self.runtime()

        let report = runtime.award(characterExperience: 60)

        #expect(!report.didLevel)
        #expect(report.carriedExperience == 60)
        #expect(runtime.level == 1)
        #expect(runtime.state.perkPoints == 0)
    }

    /// Crossing the threshold raises the level, grants one perk point and owes
    /// one attribute pick, and carries the surplus.
    @Test func crossingTheThresholdLevelsAndCarries() {
        let (runtime, _) = self.runtime()

        let report = runtime.award(characterExperience: 130)

        #expect(report.previousLevel == 1)
        #expect(report.level == 2)
        #expect(report.levelsGained == 1)
        #expect(report.carriedExperience == 30)
        #expect(report.perkPoints == 1)
        #expect(report.pendingAttributePicks == 1)
    }

    /// Several awards accumulate against the moving threshold, which is the
    /// carry rule across more than one level-up: 100 leaves level 1, then 125
    /// leaves level 2.
    @Test func experienceCarriesAcrossSeveralAwards() {
        let (runtime, _) = self.runtime()

        runtime.award(characterExperience: 80)
        runtime.award(characterExperience: 80)

        #expect(runtime.level == 2)
        #expect(runtime.state.experience == 60)

        runtime.award(characterExperience: 65)

        #expect(runtime.level == 3)
        #expect(runtime.state.experience == 0)
        #expect(runtime.perkPoints == 2)
        #expect(runtime.state.pendingAttributePicks == 2)
    }

    /// One award may buy several levels, and each one owes its own pick — the
    /// "if you gained 4 levels you will be prompted to make 4 choices" rule.
    @Test func oneAwardMayBuySeveralLevels() {
        let (runtime, _) = self.runtime()

        let report = runtime.award(characterExperience: 400)

        #expect(report.levelsGained == 3)
        #expect(report.level == 4)
        #expect(report.perkPoints == 3)
        #expect(report.pendingAttributePicks == 3)
    }

    /// The pick adds `iAVDhmsLevelUp` points as a base *offset*, so it survives
    /// re-derivation, and it fills the three values the way accepting a level
    /// does.
    @Test func anAttributePickRaisesTheChosenValue() {
        let (runtime, _) = self.runtime()
        runtime.award(characterExperience: 100)
        runtime.values.damage(.health, by: 40, on: .player)

        let result = runtime.chooseAttribute(.health)

        #expect(succeeded(result))
        #expect(runtime.values.maximums(of: .player).health == 110)
        // Accepting the level fills every value, at the new maximum.
        #expect(runtime.values.current(of: .player).health == 110)
        #expect(runtime.state.pendingAttributePicks == 0)
        #expect(runtime.state.attributePicks == [.health])
        #expect(runtime.state.pickCount(of: .health) == 1)
    }

    /// Whether a progress write was accepted, spelled once so the cases below
    /// read as the rule they check rather than as pattern matching.
    private func succeeded(_ result: PlayerProgressResult) -> Bool {
        if case .success = result {
            return true
        }
        return false
    }

    /// A stamina pick raises carry weight by `fLevelUpCarryWeightMod` beside
    /// the ten stamina, and a health pick does not.
    @Test func aStaminaPickAlsoRaisesCarryWeight() {
        let (runtime, _) = self.runtime()
        runtime.award(characterExperience: 400)

        runtime.chooseAttribute(.stamina)

        #expect(runtime.values.maximums(of: .player).stamina == 110)
        #expect(runtime.values.baseValue(
            at: ActorValueIdentity.carryWeightIndex, on: .player
        ) == 305)

        runtime.chooseAttribute(.health)

        #expect(runtime.values.baseValue(
            at: ActorValueIdentity.carryWeightIndex, on: .player
        ) == 305)
        #expect(runtime.state.attributePicks == [.stamina, .health])
    }

    /// A pick nobody is owed is refused rather than handing out free points.
    @Test func anUnearnedPickIsRefused() {
        let (runtime, _) = self.runtime()

        let result = runtime.chooseAttribute(.magicka)

        #expect(result == .failure(.noAttributePickOwed))
        #expect(runtime.values.maximums(of: .player).magicka == 100)
    }

    /// Spending from an empty pool is refused.
    @Test func spendingWithNoPerkPointsIsRefused() {
        let (runtime, _) = self.runtime()

        #expect(runtime.spendPerkPoint() == .failure(.noPerkPoints))
    }

    /// `Game.ModPerkPoints` adds and removes, floors at zero and caps at the
    /// documented 255.
    @Test func perkPointsClampToTheDocumentedBounds() {
        let (runtime, _) = self.runtime()

        #expect(runtime.modifyPerkPoints(by: 3).perkPoints == 3)
        #expect(runtime.modifyPerkPoints(by: -10).perkPoints == 0)
        #expect(runtime.modifyPerkPoints(by: 1000).perkPoints == 255)
        #expect(runtime.modifyPerkPoints(by: 1).perkPoints == 255)
    }

    /// The live level is published to the shared source, which is what every
    /// `PC Level Mult` derivation reads.
    @Test func theLevelIsPublishedToTheSharedSource() {
        let source = PlayerLevelSource()
        let (runtime, _) = self.runtime(levelSource: source)

        #expect(source.level == 1)

        runtime.award(characterExperience: 400)

        #expect(source.level == 4)
        #expect(runtime.level == 4)
    }

    /// A restored component is what the runtime reads, so a reloaded session
    /// carries on from the saved level rather than from scratch.
    @Test func aStoredComponentIsWhatTheRuntimeReads() {
        let (runtime, store) = self.runtime()

        store.set(
            PlayerProgressState(level: 12, experience: 40, perkPoints: 2),
            for: .player
        )

        #expect(runtime.level == 12)
        #expect(runtime.perkPoints == 2)
        // (12 + 3) * 25.
        #expect(runtime.experienceForNextLevel == 375)
    }
}
