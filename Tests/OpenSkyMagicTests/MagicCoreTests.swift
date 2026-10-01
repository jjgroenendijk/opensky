// The pure rules of the magic shell: reach, game day, selection, probes and
// outcome sentences.

@testable import OpenSkyFormatsESM
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import Testing

struct MagicCoreTests {
    @Test func castReachTakesTheSmallerPositiveBound() {
        #expect(MagicCore.castReach(within: 500, ceiling: 4000) == 500)
        #expect(MagicCore.castReach(within: 0, ceiling: 4000) == 4000)
        #expect(MagicCore.castReach(within: 9000, ceiling: 4000) == 4000)
        #expect(MagicCore.castReach(within: 0, ceiling: 0) == MagicCore.fallbackReach)
    }

    @Test func theGameDayRoundsDownAndClamps() {
        #expect(MagicCore.gameDay(2.9) == 2)
        #expect(MagicCore.gameDay(-0.5) == -1)
        #expect(MagicCore.gameDay(.nan) == 0)
        #expect(MagicCore.gameDay(.infinity) == 0)
        #expect(MagicCore.gameDay(1e12) == Int32.max)
        #expect(MagicCore.gameDay(-1e12) == Int32.min)
    }

    @Test func theSelectionClampsAndWraps() {
        #expect(MagicCore.clampedSelection(5, count: 3) == 2)
        #expect(MagicCore.clampedSelection(-1, count: 3) == 0)
        #expect(MagicCore.nextSelection(after: 0, count: 3) == 1)
        #expect(MagicCore.nextSelection(after: 2, count: 3) == 0)
        // A selection past the end clamps first, then wraps.
        #expect(MagicCore.nextSelection(after: 7, count: 3) == 0)
    }

    @Test func withoutAReadiedSpellTheProbesSayso() {
        let probes = MagicCore.conditionProbes(readied: nil)
        #expect(probes.map(\.function) == [214, 223, 264, 570, 571, 572, 632, 699])
        #expect(probes[2].parameter == 0)
        #expect(probes[2].line(value: "0") == "HasSpell(no readied spell) -> 0")
    }

    @Test func outcomeSentences() {
        #expect(MagicCore.dispelText(removed: 0) == "No effect was acting on the player.")
        #expect(MagicCore.dispelText(removed: 2) == "Dispelled 2 effect(s) on the player.")
        #expect(MagicCore.startSpellsText(granted: 0, held: 0)
            == "Every start spell was already known.")
        #expect(MagicCore.consumeText(name: "Potion", outcome: nil) == "Could not consume Potion.")
        #expect(MagicCore.castText(.ignored) == "Nothing to cast in that hand.")
        #expect(MagicCore.castText(.released(spell: .player, heldSeconds: 1.5, magickaSpent: 30))
            == "Maintained for 1.5s, 30 magicka spent.")
    }
}
