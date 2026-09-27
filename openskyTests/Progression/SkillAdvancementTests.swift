// The skill-advancement formulas (issue #498, roadmap item 20.5), asserted
// against hand-computed values.
//
// Every number here is either quoted from UESP "Skyrim:Leveling" or worked out
// from the formula it states, so a change to the arithmetic fails here before
// it reaches a session. The parameters are the real ones this machine's
// `Skyrim.esm` carries — `AVOneHanded` 6.3 / 0 / 2 / 0 and `AVLockpicking`
// 45 / 10 / 0.25 / 300 — stated in code rather than read from a plugin, which
// is what `SkillAdvancementRealDataTests` checks the install still says.

import Foundation
@testable import opensky
import Testing

struct SkillAdvancementTests {
    private static let oneHanded = SkillUseParameters(
        useMultiplier: 6.3,
        useOffset: 0,
        improveMultiplier: 2,
        improveOffset: 0
    )
    private static let lockpicking = SkillUseParameters(
        useMultiplier: 45,
        useOffset: 10,
        improveMultiplier: 0.25,
        improveOffset: 300
    )

    // MARK: - Experience for one use

    /// "Skill Use Mult * (base XP * skill specific multipliers) + Skill Use
    /// Offset": ten points of base weapon damage at One-Handed's 6.3 is 63.
    @Test func oneUseIsTheMultiplierTimesTheAmount() {
        #expect(
            SkillAdvancement.experience(forUse: 10, parameters: Self.oneHanded) == 63
        )
    }

    /// The wiki's own worked example of the offset: "if the game wants to award
    /// 50 XP to the Lockpicking skill (Skill Use Mult 45 and Skill Use Offset
    /// 10) ... This results in: 45*(50)+10=2260 XP."
    @Test func theOffsetIsAddedAfterTheMultiplier() {
        #expect(
            SkillAdvancement.experience(forUse: 50, parameters: Self.lockpicking) == 2260
        )
    }

    /// A non-use is worth nothing at all, offset included: a stream of
    /// zero-damage hits must not level Lockpicking ten experience at a time.
    @Test func anEmptyUseIsWorthNothing() {
        #expect(SkillAdvancement.experience(forUse: 0, parameters: Self.lockpicking) == 0)
        #expect(SkillAdvancement.experience(forUse: -5, parameters: Self.lockpicking) == 0)
        #expect(
            SkillAdvancement.experience(forUse: .nan, parameters: Self.lockpicking) == 0
        )
    }

    // MARK: - The threshold curve

    /// The wiki's worked threshold: "if you want to level Lockpicking (Skill
    /// Improve Mult 0.25, Skill Improve Offset 300) from level 15 to 16: 0.25 *
    /// 15^1.95 + 300 = 349.1267420446517".
    @Test func theThresholdIsTheImproveCurveAtTheCurrentLevel() {
        let cost = SkillAdvancement.threshold(
            atSkillLevel: 15, parameters: Self.lockpicking
        )
        #expect(abs(cost - 349.126_74) < 0.01)
    }

    /// The exponent is the game setting, not a constant: the same threshold
    /// with a curve of 1 is the linear reading of the same two parameters.
    @Test func theCurveComesFromTheGameSetting() {
        let cost = SkillAdvancement.threshold(
            atSkillLevel: 15,
            parameters: Self.lockpicking,
            settings: SkillAdvancementSettings(useCurve: 1, characterExperiencePerRank: 1)
        )
        #expect(abs(cost - (0.25 * 15 + 300)) < 0.001)
    }

    /// Parameters that make the threshold zero or negative are "no
    /// advancement", never "free": the alternative would take a skill to its
    /// ceiling on the first blow.
    @Test func anImpossibleThresholdIsReportedAsZero() {
        let free = SkillUseParameters(
            useMultiplier: 1, useOffset: 0, improveMultiplier: 0, improveOffset: 0
        )
        #expect(SkillAdvancement.threshold(atSkillLevel: 20, parameters: free) == 0)

        let outcome = SkillAdvancement.advance(
            experience: 1_000_000, from: 20, parameters: free
        )
        #expect(outcome.levelsGained == 0)
        #expect(outcome.level == 20)
    }

    // MARK: - Character experience

    /// "Character XP gained = Skill level acquired * fXPPerSkillRank ...
    /// Example: Training Alchemy from 20 to 21 gives 21 Character XP points."
    @Test func aSkillPointBanksItsNewLevelInCharacterExperience() {
        #expect(SkillAdvancement.characterExperience(forSkillLevel: 21) == 21)
    }

    // MARK: - Crossing the threshold

    /// Experience below the threshold accumulates and changes nothing else.
    @Test func experienceBelowTheThresholdOnlyAccumulates() {
        let outcome = SkillAdvancement.advance(
            experience: 100, from: 15, parameters: Self.lockpicking
        )
        #expect(outcome.levelsGained == 0)
        #expect(outcome.level == 15)
        #expect(outcome.carriedExperience == 100)
        #expect(outcome.characterExperience == 0)
    }

    /// The edge the carry rule is written for: experience exactly equal to the
    /// threshold advances the skill and carries nothing.
    @Test func exactlyTheThresholdAdvancesAndCarriesNothing() {
        let cost = SkillAdvancement.threshold(
            atSkillLevel: 15, parameters: Self.lockpicking
        )
        let outcome = SkillAdvancement.advance(
            experience: cost, from: 15, parameters: Self.lockpicking
        )
        #expect(outcome.levelsGained == 1)
        #expect(outcome.level == 16)
        #expect(outcome.carriedExperience == 0)
        #expect(outcome.characterExperience == 16)
    }

    /// The overshoot carries onto the next level rather than being thrown away.
    @Test func theRemainderCarriesToTheNextLevel() {
        let cost = SkillAdvancement.threshold(
            atSkillLevel: 15, parameters: Self.lockpicking
        )
        let outcome = SkillAdvancement.advance(
            experience: cost + 25, from: 15, parameters: Self.lockpicking
        )
        #expect(outcome.levelsGained == 1)
        #expect(abs(outcome.carriedExperience - 25) < 0.01)
    }

    /// One advance can cross several thresholds, and each banks its own
    /// character experience: 16 + 17 for two points off level 15.
    @Test func oneAdvanceCanCrossSeveralThresholds() {
        let first = SkillAdvancement.threshold(
            atSkillLevel: 15, parameters: Self.lockpicking
        )
        let second = SkillAdvancement.threshold(
            atSkillLevel: 16, parameters: Self.lockpicking
        )
        let outcome = SkillAdvancement.advance(
            experience: first + second, from: 15, parameters: Self.lockpicking
        )
        #expect(outcome.levelsGained == 2)
        #expect(outcome.level == 17)
        #expect(outcome.carriedExperience == 0)
        #expect(outcome.characterExperience == 16 + 17)
    }

    /// A skill at the ceiling gains nothing and banks nothing, however much
    /// experience is thrown at it.
    @Test func aSkillAtTheCeilingStopsAdvancing() {
        let outcome = SkillAdvancement.advance(
            experience: 10_000_000, from: 100, parameters: Self.oneHanded
        )
        #expect(outcome.levelsGained == 0)
        #expect(outcome.level == 100)
        #expect(outcome.carriedExperience == 0)
        #expect(outcome.characterExperience == 0)
    }

    /// An advance that would run past the ceiling stops on it.
    @Test func anAdvanceStopsAtTheCeiling() {
        let outcome = SkillAdvancement.advance(
            experience: 10_000_000, from: 98, parameters: Self.lockpicking
        )
        #expect(outcome.level == 100)
        #expect(outcome.levelsGained == 2)
        #expect(outcome.carriedExperience == 0)
    }

    // MARK: - Settings

    /// A load order that authors neither setting takes the documented numbers:
    /// this machine's install authors `fSkillUseCurve` at 1.95 and no
    /// `fXPPerSkillRank` at all.
    @Test func settingsFallBackToTheDocumentedNumbers() {
        let settings = SkillAdvancementSettings.resolve(store: GameSettingStore(plugins: []))
        #expect(settings == .documentedDefaults)
        #expect(settings.useCurve == 1.95)
        #expect(settings.characterExperiencePerRank == 1)
    }
}
