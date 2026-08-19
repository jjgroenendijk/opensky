// Use to experience to skill level (issue #498, roadmap item 20.5): the
// runtime that takes a reported use, banks it in the skill's `Skill Advance`
// actor value, and spends it on a level when it crosses the threshold.
//
// Baselines are synthetic and the AVIF parameters are stated in code rather
// than read from a plugin, for the reason `ActorValueOverrideTests` uses a
// synthetic baseline: what is under test is the *relationship* between a use,
// a threshold and a stored value, not where the four numbers came from.
// `SkillAdvancementRealDataTests` is what checks the install still says them.

import Foundation
@testable import opensky
import Testing

@MainActor
struct SkillAdvancementRuntimeTests {
    /// The four skills these tests drive, by their vanilla table index
    /// (`ActorValueIdentity.vanillaNames`).
    private static let oneHanded: Int32 = 6
    private static let block: Int32 = 9
    private static let heavyArmor: Int32 = 11
    private static let destruction: Int32 = 20

    /// One-Handed as this machine's `Skyrim.esm` authors it, and a cheap skill
    /// beside it so a level-up is one blow away rather than a hundred.
    private static let parameters: [Int32: SkillUseParameters] = [
        oneHanded: SkillUseParameters(
            useMultiplier: 6.3, useOffset: 0, improveMultiplier: 2, improveOffset: 0
        ),
        block: SkillUseParameters(
            useMultiplier: 8.1, useOffset: 0, improveMultiplier: 2, improveOffset: 0
        ),
        heavyArmor: SkillUseParameters(
            useMultiplier: 3.8, useOffset: 0, improveMultiplier: 2, improveOffset: 0
        ),
        destruction: SkillUseParameters(
            useMultiplier: 1.35, useOffset: 0, improveMultiplier: 2, improveOffset: 0
        )
    ]

    private func runtime(
        skills: [Int32: Float] = [:]
    ) -> (SkillAdvancementRuntime, WorldStateStore) {
        let store = WorldStateStore()
        var general = skills
        for index in ActorValueIdentity.skillIndices where general[index] == nil {
            general[index] = ActorValueIdentity.skillFloor
        }
        let baselines = ActorValueBaselineResolver(
            fallback: ActorValueBaseline(
                maximums: ActorValues(repeating: 100),
                regenPercentPerSecond: .zero,
                general: general
            )
        )
        let values = ActorValueRuntime(store: store, baselines: baselines)
        return (
            SkillAdvancementRuntime(
                values: values,
                parameters: SkillUseParameterSource(table: Self.parameters)
            ),
            store
        )
    }

    private func advanceSlot(_ skill: Int32) throws -> Int32 {
        try #require(ActorValueIdentity.skillAdvanceIndex(forSkill: skill))
    }

    // MARK: - Storage

    /// A blow's experience lands in the skill's own `Skill Advance` actor
    /// value, which is what makes it readable through `GetActorValue` and
    /// persistent through the ordinary actor-value save path.
    @Test func experienceIsStoredInTheSkillAdvanceActorValue() throws {
        var (runtime, _) = runtime()

        let report = runtime.record(SkillUseEvent(
            actor: .player, action: .weaponHit(.sword), amount: 10
        ))

        let stored = try runtime.values.baseValue(
            at: advanceSlot(Self.oneHanded), on: .player
        )
        #expect(report?.skill == Self.oneHanded)
        #expect(report?.experience == 63)
        #expect(stored == 63)
        #expect(runtime.experience(forSkill: Self.oneHanded, on: .player) == 63)
    }

    /// Uses accumulate rather than replace.
    @Test func usesAccumulate() {
        var (runtime, _) = runtime()

        for _ in 0 ..< 3 {
            runtime.record(SkillUseEvent(
                actor: .player, action: .weaponHit(.sword), amount: 10
            ))
        }

        #expect(runtime.experience(forSkill: Self.oneHanded, on: .player) == 189)
    }

    // MARK: - Levelling

    /// Crossing the threshold raises the skill's base by one, leaves the
    /// remainder on the skill, and banks the new level's character experience.
    @Test func crossingTheThresholdRaisesTheSkillAndBanksCharacterExperience() {
        var (runtime, _) = runtime()
        // 2 * 15^1.95 = 415.36 experience to leave level 15, which is one
        // enormous blow rather than a fight.
        let threshold = runtime.threshold(forSkill: Self.oneHanded, on: .player)

        let report = runtime.record(SkillUseEvent(
            actor: .player, action: .weaponHit(.sword), amount: threshold / 6.3
        ))

        #expect(report?.didAdvance == true)
        #expect(runtime.level(ofSkill: Self.oneHanded, on: .player) == 16)
        #expect(runtime.experience(forSkill: Self.oneHanded, on: .player) < 0.01)
        #expect(runtime.progress.skillIncreases == 1)
        #expect(runtime.progress.bankedExperience == 16)
        #expect(runtime.tally.advances == 1)
    }

    /// The threshold moves with the skill, so the second point costs more than
    /// the first.
    @Test func theThresholdRisesWithTheSkill() {
        var (runtime, _) = runtime()
        let first = runtime.threshold(forSkill: Self.oneHanded, on: .player)

        runtime.advance(skill: Self.oneHanded, byUse: first / 6.3, on: .player)

        #expect(runtime.threshold(forSkill: Self.oneHanded, on: .player) > first)
    }

    /// A trained skill survives re-derivation, because the level-up writes a
    /// base *offset* through `ActorValueRuntime` (item 20.3's rule).
    @Test func aTrainedSkillRidesOnTopOfItsBaseline() {
        let store = WorldStateStore()
        let baselines = { (floor: Float) in
            ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 100),
                    regenPercentPerSecond: .zero,
                    general: [Self.oneHanded: floor]
                )
            )
        }
        var trained = SkillAdvancementRuntime(
            values: ActorValueRuntime(store: store, baselines: baselines(15)),
            parameters: SkillUseParameterSource(table: Self.parameters)
        )
        trained.increment(skill: Self.oneHanded, on: .player)

        // The same stored state, read against records that now author 20.
        let rederived = ActorValueRuntime(store: store, baselines: baselines(20))
        #expect(rederived.baseValue(at: Self.oneHanded, on: .player) == 21)
    }

    // MARK: - What is dropped

    /// Skills advance for the player alone; an NPC's stay derived.
    @Test func anNPCsUseIsDropped() {
        var (runtime, _) = runtime()
        let bandit = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x1234)

        let report = runtime.record(SkillUseEvent(
            actor: bandit, action: .weaponHit(.sword), amount: 10
        ))

        #expect(report == nil)
        #expect(runtime.tally.nonPlayerUses == 1)
    }

    /// An unarmed strike claims no skill: "Unarmed combat does not have its own
    /// skill tree and cannot be developed like other skills."
    @Test func anUnarmedStrikeClaimsNoSkill() {
        var (runtime, _) = runtime()

        let report = runtime.record(SkillUseEvent(
            actor: .player, action: .weaponHit(.handToHand), amount: 10
        ))

        #expect(report == nil)
        #expect(runtime.tally.unclaimedUses == 1)
    }

    /// A session with no AVIF parameters converts nothing and says so, rather
    /// than inventing multipliers.
    @Test func aSessionWithNoParametersConvertsNothing() {
        let store = WorldStateStore()
        var runtime = SkillAdvancementRuntime(
            values: ActorValueRuntime(
                store: store,
                baselines: ActorValueBaselineResolver(
                    fallback: ActorValueBaseline(
                        maximums: ActorValues(repeating: 100),
                        regenPercentPerSecond: .zero
                    )
                )
            )
        )

        let report = runtime.record(SkillUseEvent(
            actor: .player, action: .weaponHit(.sword), amount: 10
        ))

        #expect(report == nil)
        #expect(runtime.tally.missingParameters == 1)
        #expect(!runtime.tally.isClean)
    }

    // MARK: - Which skill a use credits

    /// Each weapon family credits its own skill, and a bow credits Archery.
    @Test func theWeaponFamilyPicksTheSkill() {
        #expect(
            SkillUseAction.weaponHit(.mace).skillIndex
                == ActorValueIdentity.index(named: "One-Handed")
        )
        #expect(
            SkillUseAction.weaponHit(.battleaxe).skillIndex
                == ActorValueIdentity.index(named: "Two-Handed")
        )
        #expect(
            SkillUseAction.weaponHit(.crossbow).skillIndex
                == ActorValueIdentity.index(named: "Archery")
        )
        #expect(SkillUseAction.weaponHit(.torch).skillIndex == nil)
    }

    /// An armoured hit credits the armour worn, scaled by how much of it there
    /// is, and a mixed set credits one skill only.
    @Test func armourWornDecidesWhichSkillAHitCredits() {
        var (runtime, _) = runtime()
        runtime.wornArmor = { _ in WornArmorProfile(heavyPieces: 3, lightPieces: 1) }

        let report = runtime.record(SkillUseEvent(
            actor: .player, action: .armorHit, amount: 10
        ))

        #expect(report?.skill == Self.heavyArmor)
        // Three pieces of heavy armour: 3 * 10 base experience at 3.8.
        #expect(report?.experience == 114)
    }

    /// An unarmoured character learns nothing from being hit.
    @Test func anUnarmouredHitCreditsNothing() {
        var (runtime, _) = runtime()

        let report = runtime.record(SkillUseEvent(
            actor: .player, action: .armorHit, amount: 10
        ))

        #expect(report == nil)
        #expect(runtime.tally.unclaimedUses == 1)
    }

    /// A cast credits the school its MGEF names.
    @Test func aCastCreditsTheEffectsMagicSkill() {
        var (runtime, _) = runtime()

        let report = runtime.record(SkillUseEvent(
            actor: .player, action: .spellEffect(skill: Self.destruction), amount: 20
        ))

        #expect(report?.skill == Self.destruction)
        #expect(report?.experience == 27)
    }

    /// An effect naming an actor value that is not a skill credits nothing.
    @Test func anEffectOutsideTheSkillsCreditsNothing() {
        var (runtime, _) = runtime()

        let report = runtime.record(SkillUseEvent(
            actor: .player, action: .spellEffect(skill: 24), amount: 20
        ))

        #expect(report == nil)
    }

    // MARK: - The scripted paths

    /// `Game.AdvanceSkill` takes a use amount and runs the same conversion a
    /// blow does.
    @Test func advanceSkillTakesAUseAmount() {
        var (runtime, _) = runtime()

        runtime.advance(skill: Self.block, byUse: 10, on: .player)

        #expect(runtime.experience(forSkill: Self.block, on: .player) == 81)
        #expect(runtime.level(ofSkill: Self.block, on: .player) == 15)
    }

    /// `Game.IncrementSkill` raises the skill by a whole point and leaves the
    /// experience earned by use exactly where it was.
    @Test func incrementSkillRaisesTheLevelAndKeepsTheProgress() {
        var (runtime, _) = runtime()
        runtime.advance(skill: Self.block, byUse: 10, on: .player)

        let report = runtime.increment(skill: Self.block, on: .player)

        #expect(report?.level == 16)
        #expect(runtime.level(ofSkill: Self.block, on: .player) == 16)
        #expect(runtime.experience(forSkill: Self.block, on: .player) == 81)
        #expect(runtime.progress.bankedExperience == 16)
    }

    /// A skill at the ceiling refuses the point rather than reporting one it
    /// did not give.
    @Test func incrementSkillRefusesASkillAtTheCeiling() {
        var (runtime, _) = runtime(skills: [Self.block: 100])

        #expect(runtime.increment(skill: Self.block, on: .player) == nil)
        #expect(runtime.level(ofSkill: Self.block, on: .player) == 100)
    }
}
