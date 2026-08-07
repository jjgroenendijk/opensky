// Actor-value derivation tests (issue #194): the documented formula, the exact
// apportionment method, and level resolution.
//
// Every expected number below is either quoted from the source that documents
// it or hand-computed from the quoted formula, never taken from an
// implementation run. The sources are cited in
// `opensky/Actors/ActorValueDerivation.swift`.

import Foundation
@testable import opensky
import Testing

struct ActorValueDerivationTests {
    private let nord = Race.Stats(
        startingHealth: 50,
        startingMagicka: 50,
        startingStamina: 50,
        healthRegenPercent: 0.7,
        magickaRegenPercent: 3,
        staminaRegenPercent: 5
    )

    private func weights(
        _ health: UInt8,
        _ magicka: UInt8,
        _ stamina: UInt8
    ) -> CharacterClass.AttributeWeights {
        CharacterClass.AttributeWeights(health: health, magicka: magicka, stamina: stamina)
    }

    // MARK: - Non-auto-calc

    /// "If the auto-calc flag for an NPC isn't set, all attributes are
    /// calculated just as: Attribute = [Racial bonus] + [NPC offset]."
    /// (UESP CLAS)
    @Test func withoutAutoCalcTheValuesAreRacialPlusOffset() {
        let inputs = ActorValueInputs(
            race: nord,
            stats: ActorBase.Stats(
                levelWord: 20,
                healthOffset: 25,
                magickaOffset: -10,
                staminaOffset: 0
            ),
            autoCalculatesStats: false,
            attributeWeights: weights(1, 1, 1)
        )
        let values = ActorValueDerivation.baseValues(inputs: inputs)
        #expect(values == ActorValues(health: 75, magicka: 40, stamina: 50))
    }

    /// A negative offset larger than the racial base floors at zero rather than
    /// producing a negative maximum.
    @Test func aNegativeOffsetFloorsAtZero() {
        let inputs = ActorValueInputs(
            race: nord,
            stats: ActorBase.Stats(healthOffset: -200)
        )
        #expect(ActorValueDerivation.baseValues(inputs: inputs).health == 0)
    }

    /// Level does not matter without auto-calc: the level term is the only
    /// thing the flag gates.
    @Test func withoutAutoCalcLevelChangesNothing() {
        let low = ActorValueInputs(race: nord, stats: ActorBase.Stats(levelWord: 1))
        let high = ActorValueInputs(race: nord, stats: ActorBase.Stats(levelWord: 50))
        #expect(
            ActorValueDerivation.baseValues(inputs: low)
                == ActorValueDerivation.baseValues(inputs: high)
        )
    }

    // MARK: - Auto-calc

    /// A level-1 auto-calc actor gains nothing: the formula's level term is
    /// `(Level - 1)`, so it is zero.
    @Test func atLevelOneAutoCalcMatchesRacialPlusOffset() {
        let inputs = ActorValueInputs(
            race: nord,
            stats: ActorBase.Stats(levelWord: 1, healthOffset: 50, magickaOffset: 50),
            autoCalculatesStats: true,
            attributeWeights: weights(1, 2, 3)
        )
        let values = ActorValueDerivation.baseValues(inputs: inputs)
        #expect(values == ActorValues(health: 100, magicka: 100, stamina: 50))
    }

    /// The Creation Kit's own worked example: "say Health = 1, Magicka = 2,
    /// Stamina = 3. An Actor at Level 7 has a total of 60 HMS points to
    /// distribute ... So the NPC has +40 Health (+10 from Health's class weight
    /// and +30 from the per-level health bonus), +20 Magicka, and +30 Stamina."
    /// (<https://ck.uesp.net/wiki/Class>)
    @Test func matchesTheCreationKitLevelSevenExample() {
        let inputs = ActorValueInputs(
            race: Race.Stats(),
            stats: ActorBase.Stats(levelWord: 7),
            autoCalculatesStats: true,
            attributeWeights: weights(1, 2, 3)
        )
        let values = ActorValueDerivation.baseValues(inputs: inputs)
        #expect(values == ActorValues(health: 40, magicka: 20, stamina: 30))
    }

    /// The rounding example from the same page: "if you have 50 HMS points to
    /// distribute, with 1/6 to Health and 4/6 to Magicka and 1/6 to Stamina,
    /// you would do Magicka first, which would receive 33 points ... Health,
    /// which would receive 8 points ... finally, Stamina would receive the
    /// remaining 9."
    @Test func matchesTheDocumentedRoundingExample() {
        let spread = ActorValueDerivation.distribute(points: 50, weights: weights(1, 4, 1))
        #expect(spread.health == 8)
        #expect(spread.magicka == 33)
        #expect(spread.stamina == 9)
    }

    /// Every point is handed out, whatever the weights, so an actor never
    /// silently loses one to rounding.
    @Test func everyPointIsDistributed() {
        let cases: [(points: Int, weights: CharacterClass.AttributeWeights)] = [
            (10, weights(1, 1, 1)),
            (14, weights(3, 1, 1)),
            (90, weights(2, 5, 7)),
            (7, weights(9, 1, 0)),
            (250, weights(4, 4, 4))
        ]
        for one in cases {
            let spread = ActorValueDerivation.distribute(points: one.points, weights: one.weights)
            #expect(spread.health + spread.magicka + spread.stamina == Float(one.points))
        }
    }

    /// An all-equal-weight leftover lands on stamina first — "in reverse actor
    /// value index order (stamina, magicka, then health)" (UESP CLAS).
    @Test func anEqualWeightLeftoverGoesToStaminaFirst() {
        let spread = ActorValueDerivation.distribute(points: 10, weights: weights(1, 1, 1))
        #expect(spread.health == 3)
        #expect(spread.magicka == 3)
        #expect(spread.stamina == 4)
    }

    /// A class with no weights spreads nothing rather than dividing by zero,
    /// which would put a NaN into an actor's maximum health.
    @Test func zeroWeightsSpreadNothing() {
        #expect(ActorValueDerivation.distribute(points: 100, weights: weights(0, 0, 0))
            == .zero)

        let inputs = ActorValueInputs(
            race: nord,
            stats: ActorBase.Stats(levelWord: 10),
            autoCalculatesStats: true
        )
        let values = ActorValueDerivation.baseValues(inputs: inputs)
        // Health still gains its flat per-level bonus, which is "independent of
        // its weight" (UESP CLAS).
        #expect(values == ActorValues(health: 95, magicka: 50, stamina: 50))
    }

    /// The two game settings come from GMSTs, so a load order that changes them
    /// changes the derivation.
    @Test func theLevelSettingsDriveTheSpread() {
        let inputs = ActorValueInputs(
            race: Race.Stats(),
            stats: ActorBase.Stats(levelWord: 3),
            autoCalculatesStats: true,
            attributeWeights: weights(1, 0, 0)
        )
        let doubled = ActorValueLevelSettings(pointsPerLevel: 20, healthBonusPerLevel: 0)
        let values = ActorValueDerivation.baseValues(inputs: inputs, settings: doubled)
        #expect(values == ActorValues(health: 40, magicka: 0, stamina: 0))
    }

    // MARK: - Level

    @Test func aFixedLevelIsTheACBSWord() {
        let inputs = ActorValueInputs(stats: ActorBase.Stats(levelWord: 17))
        #expect(ActorValueDerivation.level(inputs: inputs, playerLevel: 40) == 17)
    }

    /// "Level Mult: The level of the player is multiplied by this field",
    /// stored as the multiplier times 1000, then clamped by Calc Min / Calc Max
    /// (<https://ck.uesp.net/wiki/Stats_Tab>).
    @Test func aPlayerLevelMultiplierScalesAndClamps() {
        let inputs = ActorValueInputs(
            stats: ActorBase.Stats(levelWord: 1500, calcMinLevel: 6, calcMaxLevel: 20),
            usesPlayerLevelMultiplier: true
        )
        #expect(ActorValueDerivation.level(inputs: inputs, playerLevel: 10) == 15)
        #expect(ActorValueDerivation.level(inputs: inputs, playerLevel: 1) == 6)
        #expect(ActorValueDerivation.level(inputs: inputs, playerLevel: 40) == 20)
    }

    /// A zero bound means unbounded, which is how the Creation Kit leaves both
    /// fields when the designer sets no clamp.
    @Test func zeroBoundsDoNotClamp() {
        let inputs = ActorValueInputs(
            stats: ActorBase.Stats(levelWord: 1000),
            usesPlayerLevelMultiplier: true
        )
        #expect(ActorValueDerivation.level(inputs: inputs, playerLevel: 42) == 42)
    }

    /// Every level floors at 1, which is the level the race's starting
    /// attributes are defined for.
    @Test func everyLevelFloorsAtOne() {
        let zeroWord = ActorValueInputs(stats: ActorBase.Stats(levelWord: 0))
        #expect(ActorValueDerivation.level(inputs: zeroWord, playerLevel: 1) == 1)
        let zeroMultiplier = ActorValueInputs(
            stats: ActorBase.Stats(levelWord: 0),
            usesPlayerLevelMultiplier: true
        )
        #expect(ActorValueDerivation.level(inputs: zeroMultiplier, playerLevel: 50) == 1)
    }
}

struct ActorValueLevelSettingsTests {
    /// The Creation Kit documents 10 and 5 as the defaults, which is what a
    /// session with no loaded plugin uses.
    @Test func documentedDefaults() {
        #expect(ActorValueLevelSettings.documentedDefaults.pointsPerLevel == 10)
        #expect(ActorValueLevelSettings.documentedDefaults.healthBonusPerLevel == 5)
    }

    @Test func anEmptyStoreResolvesToTheDefaults() {
        let settings = ActorValueLevelSettings.resolve(store: GameSettingStore(plugins: []))
        #expect(settings == .documentedDefaults)
    }
}
