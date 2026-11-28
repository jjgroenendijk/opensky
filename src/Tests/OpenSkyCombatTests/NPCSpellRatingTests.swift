// The game's spell rating, checked on the worked examples of the AI spell use page.

@testable import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct NPCSpellRatingTests {
    private typealias Rated = NPCSpellRating.RatedEffect

    /// FireDamageFFAimed: magnitude 25, taper weight 0.3 over 1 s.
    private static let firebolt = Rated(
        archetype: 0, actorValue: 24, hostile: true, magnitude: 25, taperWeight: 0.3,
        taperDuration: 1
    )

    @Test func aFireboltScoresItsMagnitudeTimesItsTaper() {
        let score = NPCSpellRating.score(
            of: Self.firebolt,
            targetsSelf: false,
            concentration: false
        )
        #expect(abs(score - 28.75) < 0.001)
    }

    @Test func anIceSpikeAddsItsStaminaShare() {
        let spike = Rated(
            archetype: 5, actorValue: 24, secondActorValue: 26, secondActorValueWeight: 1,
            hostile: true, noDuration: true, magnitude: 25, taperWeight: 0.3, taperDuration: 1
        )
        let score = NPCSpellRating.score(of: spike, targetsSelf: false, concentration: false)
        #expect(abs(score - 33.25) < 0.001)
    }

    @Test func anEffectOutsideTheTableScoresNothing() {
        let slow = Rated(archetype: 34, actorValue: 31, hostile: true, magnitude: 50)
        #expect(NPCSpellRating.score(of: slow, targetsSelf: false, concentration: false) == 0)
        let heal = Rated(archetype: 0, actorValue: 24, magnitude: 50)
        #expect(NPCSpellRating.score(of: heal, targetsSelf: false, concentration: false) == 0)
        #expect(NPCSpellRating.score(of: heal, targetsSelf: true, concentration: false) == 50)
    }

    @Test func aDamageEffectWithNoMagnitudeScoresNothing() {
        let empty = Rated(actorValue: 24, hostile: true)
        #expect(NPCSpellRating.score(of: empty, targetsSelf: false, concentration: false) == 0)
    }

    @Test func aCostRowAndAScriptRowIgnoreTheMagnitude() {
        let paralysis = Rated(archetype: 21, actorValue: 53, hostile: true, magnitude: 1, cost: 4)
        #expect(NPCSpellRating.score(of: paralysis, targetsSelf: false, concentration: false) == 80)
        let script = Rated(archetype: 1, hostile: true, magnitude: 99, scriptAIScore: 7)
        #expect(NPCSpellRating.score(of: script, targetsSelf: false, concentration: false) == 7)
    }

    @Test func concentrationCountsThreeSecondsAndNoMagnitudeCountsNone() {
        let flames = Rated(archetype: 0, actorValue: 24, hostile: true, magnitude: 8, duration: 9)
        #expect(NPCSpellRating.score(of: flames, targetsSelf: false, concentration: true) == 24)
        var silent = flames
        silent.noMagnitude = true
        #expect(NPCSpellRating.score(of: silent, targetsSelf: false, concentration: false) == 0)
    }

    @Test func aStoredSpellIsRatedAndALongReachCountsTwice() throws {
        let effect = ESMFixture.record(
            "MGEF",
            formID: 0x60,
            data:
            ESMFixture.field("EDID", ESMFixture.zstring("TestFrost"))
                + ESMFixture.field("DATA", MagicEffectFixture.data(archetype: 5))
        )
        let file = try SpellStoreFixture.plugin(records: [
            effect,
            ESMFixture.record("SPEL", formID: 0x42, data: SpellStoreFixture.spellFields(
                editorID: "TestSpike", name: "Spike", spit: SpellFixture.spit(),
                effects: [SpellStoreFixture.EffectSpec(0x60, magnitude: 25)]
            ))
        ])
        let spell = try #require(SpellStore(plugins: [("Base.esm", file)])
            .spell(editorID: "TestSpike"))
        // Health 25 x 1.5, then Magicka 25 x 0.4 x 1.5 x 0.5: taper weight 0.5 over 2 s.
        #expect(abs(NPCSpellRating.score(of: spell, range: 1000) - 45) < 0.001)
        #expect(abs(NPCSpellRating.score(of: spell, range: 2000) - 90) < 0.001)
    }
}
