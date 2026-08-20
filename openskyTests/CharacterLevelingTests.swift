// The character level curve (issue #499, roadmap item 20.6): what the next
// level costs, what a running total is worth, and what banking experience does
// to a level.
//
// Every number here is hand-computable from the two settings, and the ones UESP
// prints outright — 100 to leave level 1, 1300 to leave level 49, and the
// closed form of the running total — are asserted against rather than restated,
// so a change to either formula fails here before it reaches a session.
// `CharacterLevelingRealDataTests` is what checks the install still authors the
// two settings this suite assumes.

import Foundation
@testable import opensky
import Testing

struct CharacterLevelingTests {
    /// "100 XP is required to advance from level 1 to level 2, and 1300 XP is
    /// required to advance from level 49 to 50. This is consistent across all
    /// levels. (70→71 follows the same formula as 3→4)"
    /// (<https://en.uesp.net/wiki/Skyrim:Leveling>)
    @Test func theThresholdMatchesTheWorkedNumbers() {
        #expect(CharacterLeveling.experienceForNextLevel(atLevel: 1) == 100)
        #expect(CharacterLeveling.experienceForNextLevel(atLevel: 49) == 1300)
        #expect(CharacterLeveling.experienceForNextLevel(atLevel: 3) == 150)
        #expect(CharacterLeveling.experienceForNextLevel(atLevel: 70) == 1825)
    }

    /// "XP required to level up your character = (Current level + 3) * 25",
    /// which is the same curve spelled without the settings.
    @Test func theThresholdMatchesTheSettinglessSpelling() {
        for level in 1 ... 80 {
            #expect(
                CharacterLeveling.experienceForNextLevel(atLevel: level)
                    == Float(level + 3) * 25
            )
        }
    }

    /// "XP required to go from level 1 to level N = 12.5 * N^2 + 62.5 * N - 75".
    /// The sum is computed from the settings rather than from those constants,
    /// so this is what ties the two readings together.
    @Test func theRunningTotalMatchesTheClosedForm() {
        for level in 1 ... 60 {
            let count = Float(level)
            let closedForm = 12.5 * count * count + 62.5 * count - 75
            #expect(
                abs(CharacterLeveling.cumulativeExperience(toLevel: level) - closedForm) < 0.5
            )
        }
    }

    /// "FLOOR(-2.5 + SQRT(8 * XP + 1225) / 10)" is UESP's inverse of that sum.
    /// Spending the exact running total for level N from level 1 must land on
    /// N, which is the same statement without the square root.
    @Test func spendingTheRunningTotalReachesThatLevel() {
        for level in 2 ... 40 {
            let outcome = CharacterLeveling.advance(
                experience: CharacterLeveling.cumulativeExperience(toLevel: level),
                from: 1
            )
            #expect(outcome.level == level)
            #expect(outcome.levelsGained == level - 1)
            #expect(outcome.carriedExperience < 0.5)
        }
    }

    /// Experience short of the threshold buys nothing and stays banked.
    @Test func experienceBelowTheThresholdCarries() {
        let outcome = CharacterLeveling.advance(experience: 99, from: 1)

        #expect(outcome.levelsGained == 0)
        #expect(outcome.level == 1)
        #expect(outcome.carriedExperience == 99)
        #expect(!outcome.didAdvance)
    }

    /// Exactly the threshold levels the character and carries nothing, which is
    /// the edge the `>=` in the loop decides.
    @Test func experienceExactlyAtTheThresholdLevels() {
        let outcome = CharacterLeveling.advance(experience: 100, from: 1)

        #expect(outcome.levelsGained == 1)
        #expect(outcome.level == 2)
        #expect(outcome.carriedExperience == 0)
    }

    /// The surplus carries across several thresholds in one award, which is the
    /// over-training rule: 100 leaves level 1, 125 leaves level 2, 150 leaves
    /// level 3, so 400 buys three levels and leaves 25 banked.
    @Test func oneAwardCrossesSeveralThresholdsAndCarriesTheRest() {
        let outcome = CharacterLeveling.advance(experience: 400, from: 1)

        #expect(outcome.levelsGained == 3)
        #expect(outcome.level == 4)
        #expect(outcome.carriedExperience == 25)
    }

    /// A non-finite award is ignored rather than propagated, and a settings
    /// table that makes the threshold impossible reports no leveling rather
    /// than free levels.
    @Test func badNumbersLevelNothing() {
        #expect(CharacterLeveling.advance(experience: .nan, from: 5).levelsGained == 0)
        #expect(CharacterLeveling.advance(experience: -100, from: 5).carriedExperience == 0)

        let broken = CharacterLevelSettings(
            levelUpBase: 0, levelUpMultiplier: 0, attributeIncrement: 10,
            carryWeightPerStaminaPick: 5
        )
        #expect(CharacterLeveling.experienceForNextLevel(atLevel: 1, settings: broken) == 0)
        #expect(
            CharacterLeveling.advance(experience: 1_000_000, from: 1, settings: broken)
                .levelsGained == 0
        )
    }

    /// A load order that moves the settings moves the whole curve with them,
    /// which is what makes the vanilla constants a reading rather than a rule.
    @Test func movedSettingsMoveTheCurve() {
        let doubled = CharacterLevelSettings(
            levelUpBase: 150, levelUpMultiplier: 50, attributeIncrement: 10,
            carryWeightPerStaminaPick: 5
        )

        #expect(CharacterLeveling.experienceForNextLevel(atLevel: 1, settings: doubled) == 200)
        #expect(
            CharacterLeveling.advance(experience: 200, from: 1, settings: doubled).level == 2
        )
    }

    /// The settings resolver reads the float settings and the one integer
    /// setting, and falls back per setting rather than wholesale.
    @Test func settingsResolveFromTheStore() throws {
        let settings = try CharacterLevelSettings.resolve(store: settingStore())

        #expect(settings.levelUpBase == 90)
        #expect(settings.attributeIncrement == 12)
        // Untouched by the plugin, so both keep the documented number.
        #expect(settings.levelUpMultiplier == 25)
        #expect(settings.carryWeightPerStaminaPick == 5)
    }

    /// A synthetic plugin carrying one float setting and one integer setting,
    /// built in code — never an extracted record. `iAVDhmsLevelUp` is the
    /// integer, which is why the resolver reads both numeric spellings.
    private func settingStore() throws -> GameSettingStore {
        var records = setting("fXPLevelUpBase", value: 90.0.bitPattern32, formID: 1)
        records += setting("iAVDhmsLevelUp", value: UInt32(bitPattern: 12), formID: 2)
        let file = try ESMFile(
            data: ESMFixture.tes4() + ESMFixture.topGroup("GMST", contents: records)
        )
        return GameSettingStore(plugins: [("Leveling.esp", file)])
    }

    private func setting(_ editorID: String, value: UInt32, formID: UInt32) -> Data {
        var raw = value.littleEndian
        let data = withUnsafeBytes(of: &raw) { Data($0) }
        let fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("DATA", data)
        return ESMFixture.record("GMST", formID: formID, data: fields)
    }
}

extension Double {
    fileprivate var bitPattern32: UInt32 {
        Float(self).bitPattern
    }
}
