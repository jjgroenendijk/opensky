// Env-gated skill-advancement spot check over the user's read-only active load
// order (issue #498, roadmap item 20.5): the `AVSK` parameters two vanilla
// skills carry, the game settings the curve reads, and the experience a fixed
// use amount is worth against them. Derived numbers and editor IDs only — no
// game bytes leave the run.
//
// This is the pin under `SkillAdvancementTests`, which states the same four
// numbers in code. If Bethesda's records and this suite ever disagree, the
// synthetic suite is the one that is wrong.

import Foundation
@testable import opensky
import Testing

struct SkillAdvancementRealDataTests {
    /// `nonisolated` so the `.enabled(if:)` trait can read it from the sendable
    /// closure the macro builds.
    nonisolated private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// The two records this suite pins, by editor ID and by the vanilla table
    /// index each joins to.
    private static let oneHanded: Int32 = 6
    private static let lockpicking: Int32 = 14

    /// The install's own numbers, measured on this machine 2026-08-19 with
    /// `make run-cli ARGS="record AVOneHanded"` and `record AVLockpicking`.
    private static let expectedOneHanded = SkillUseParameters(
        useMultiplier: 6.3, useOffset: 0, improveMultiplier: 2, improveOffset: 0
    )
    private static let expectedLockpicking = SkillUseParameters(
        useMultiplier: 45, useOffset: 10, improveMultiplier: 0.25, improveOffset: 300
    )

    /// Every skill carries advancement parameters, and the two pinned records
    /// carry exactly the numbers the synthetic suites state.
    @Test(.enabled(if: Self.dataRoot != nil))
    func everySkillCarriesTheAuthoredAdvancementParameters() throws {
        let root = try #require(Self.dataRoot)
        let store = ActorValueInformationStoreLoader.load(root: root)
        let source = SkillUseParameterSource(store: store)

        for index in ActorValueIdentity.skillIndices {
            #expect(
                source.parameters(forSkill: index) != nil,
                "no AVSK for \(ActorValueIdentity.description(of: index))"
            )
        }
        #expect(source.parameters(forSkill: Self.oneHanded) == Self.expectedOneHanded)
        #expect(source.parameters(forSkill: Self.lockpicking) == Self.expectedLockpicking)
    }

    /// The acceptance number: pinned parameters plus the install's own
    /// `fSkillUseCurve` produce the experience and the threshold UESP works
    /// through by hand — 45 * 50 + 10 = 2260 experience for a use of 50, and
    /// 0.25 * 15^1.95 + 300 = 349.13 to leave Lockpicking level 15.
    @Test(.enabled(if: Self.dataRoot != nil))
    func pinnedParametersProduceTheDocumentedExperienceAndThreshold() throws {
        let root = try #require(Self.dataRoot)
        let store = ActorValueInformationStoreLoader.load(root: root)
        let settings = SkillAdvancementSettings.resolve(
            store: GameSettingLoader.load(root: root)
        )
        let source = SkillUseParameterSource(store: store)
        let parameters = try #require(source.parameters(forSkill: Self.lockpicking))

        // `fSkillUseCurve` is authored at 1.95; `fXPPerSkillRank` is authored by
        // no active plugin here, so it takes the documented default of 1.
        #expect(settings.useCurve == 1.95)
        #expect(settings.characterExperiencePerRank == 1)

        let experience = SkillAdvancement.experience(forUse: 50, parameters: parameters)
        #expect(experience == 2260)

        let threshold = SkillAdvancement.threshold(
            atSkillLevel: 15, parameters: parameters, settings: settings
        )
        #expect(abs(threshold - 349.126_74) < 0.01)

        // "you would need the 86th pick broken to level up": a broken pick is
        // 0.25 base experience, and the cumulative 15 -> 20 span the same page
        // works through is 1815.54.
        let perBrokenPick = SkillAdvancement.experience(
            forUse: 0.25, parameters: parameters
        )
        #expect(abs(perBrokenPick - (45 * 0.25 + 10)) < 0.0001)
    }

    /// The whole path over real parameters: a use amount lands in the skill's
    /// `Skill Advance` actor value, and enough of them raise the skill by one.
    @MainActor
    @Test(.enabled(if: Self.dataRoot != nil))
    func realParametersDriveARealLevelUp() throws {
        let root = try #require(Self.dataRoot)
        let store = WorldStateStore()
        var runtime = SkillAdvancementRuntime(
            values: ActorValueRuntime(
                store: store,
                baselines: ActorValueBaselineResolver(
                    fallback: ActorValueBaseline(
                        maximums: ActorValues(repeating: 100),
                        regenPercentPerSecond: .zero,
                        general: [Self.oneHanded: ActorValueIdentity.skillFloor]
                    )
                )
            ),
            parameters: SkillUseParameterSource(
                store: ActorValueInformationStoreLoader.load(root: root)
            ),
            settings: SkillAdvancementSettings.resolve(
                store: GameSettingLoader.load(root: root)
            )
        )
        let threshold = runtime.threshold(forSkill: Self.oneHanded, on: .player)
        #expect(threshold > 0)

        // Ten-damage swings, which is a sword's order of magnitude, until the
        // skill goes up. 6.3 experience per point of base damage puts that at
        // seven blows off the floor, and the loop is bounded so a formula change
        // fails rather than spins.
        var blows = 0
        while runtime.level(ofSkill: Self.oneHanded, on: .player) == 15, blows < 100 {
            runtime.record(SkillUseEvent(
                actor: .player, action: .weaponHit(.sword), amount: 10
            ))
            blows += 1
        }

        #expect(blows == Int((threshold / 63).rounded(.up)))
        #expect(runtime.level(ofSkill: Self.oneHanded, on: .player) == 16)
        #expect(runtime.progress.bankedExperience == 16)
        #expect(runtime.tally.isClean)
    }
}
