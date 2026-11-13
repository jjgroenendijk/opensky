// The perk card text of a perk with ranks left past an owned one.

import OpenSkyGameData
import Testing

struct ProgressionTextsTests {
    @Test func aPartOwnedPerkShowsTheNextRankAfterItsWord() {
        let texts = ProgressionTexts.vanilla
        #expect(
            texts.perkCardText(owned: "Bows do 20% more damage.", next: "Bows do 40% more damage.")
                == "Bows do 20% more damage.\nNext Rank: Bows do 40% more damage."
        )
        #expect(texts.perkCardText(owned: nil, next: "First rank.") == "First rank.")
    }
}
