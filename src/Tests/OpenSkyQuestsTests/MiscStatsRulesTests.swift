// The misc stat rules the engine counts itself: days, shouts, and the favourite lists.
// See docs/engine/statistics.md, How the game counts.

import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import Testing

struct MiscStatsRulesTests {
    private static func word(_ id: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: id)
    }

    @Test func aDayCountsTheVampireAndWerewolfDaysOnlyWhenTheirGlobalIsSet() {
        #expect(MiscStats.dayPassed(isVampire: false, isWerewolf: false) == ["Days Passed"])
        #expect(MiscStats.dayPassed(isVampire: true, isWerewolf: true) == [
            "Days Passed", "Days as a Vampire", "Days as a Werewolf"
        ])
    }

    @Test func unlockingAFirstOrLastWordCountsTheShout() {
        let (first, second, third) = (Self.word(1), Self.word(2), Self.word(3))
        let slots: [ReferenceKey: [ReferenceKey?]] = [
            Self.word(10): [first, second, third],
            // A one-word shout: its first word is also its last filled one.
            Self.word(11): [third, nil, nil]
        ]
        #expect(MiscStats.wordUnlocked(first, slots: slots) == ["Shouts Unlocked"])
        #expect(MiscStats.wordUnlocked(second, slots: slots).isEmpty)
        #expect(MiscStats.wordUnlocked(third, slots: slots).sorted() == [
            "Shouts Mastered", "Shouts Mastered", "Shouts Unlocked"
        ])
        #expect(MiscStats.shouts(with: third, slots: slots).count == 2)
    }

    @Test func theFavouriteIsTheMostUsedAndATieGoesToTheLastUse() {
        let (axe, bow) = (Self.word(20), Self.word(21))
        #expect(MiscStats.favorite(of: [axe, bow, axe]) == axe)
        #expect(MiscStats.favorite(of: [axe, bow, bow, axe]) == axe)
        #expect(MiscStats.favorite(of: [ReferenceKey]()) == nil)
        #expect(MiscStats.favorite(of: ["Destruction", "Restoration", "Restoration"])
            == "Restoration")
    }

    @Test func aUseListKeepsTheLastHundred() {
        var stats = MiscStatsState()
        for id in 0 ..< 105 {
            stats.noteUse(.weapon, of: Self.word(UInt32(id)))
        }
        #expect(stats.recentUses[.weapon]?.count == MiscStatsState.recentUseLimit)
        #expect(stats.recentUses[.weapon]?.first == Self.word(5))
        #expect(FavoriteUse.allCases.map(\.statName) == [
            "Favorite Weapon", "Favorite Spell", "Favorite Shout"
        ])
        #expect(MiscStats.stat(named: "Favorite School")?.isText == true)
        #expect(MiscStats.stat(named: "Mauls")?.isText == false)
    }
}
