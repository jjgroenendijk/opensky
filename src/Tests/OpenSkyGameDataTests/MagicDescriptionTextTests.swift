// The tag rules of a magic effect's description, from the CK wiki's Magic Effect page.

import OpenSkyGameData
import Testing

struct MagicDescriptionTextTests {
    private let values = MagicDescriptionText.Values(magnitude: 25, duration: 60, area: 15)

    @Test func theValueTagsShowTheirNumbers() {
        let text = MagicDescriptionText.filled(
            "Deals <mag> points for <dur> seconds in <area> feet.", values: values
        )
        #expect(text == "Deals 25 points for 60 seconds in 15 feet.")
    }

    @Test func aValueTheEffectLacksShowsNothing() {
        let none = MagicDescriptionText.Values(magnitude: nil, duration: nil, area: nil)
        #expect(MagicDescriptionText.filled("A<mag>B<DUR>C<area>", values: none) == "ABC")
    }

    @Test func aGlobalShowsItsValueOrNothing() {
        let text = MagicDescriptionText.filled(
            "<Global=GameHour> and <global=Missing> and <global>", values: values
        ) { $0 == "GameHour" ? 7.5 : nil }
        #expect(text == "7.5 and  and ")
    }

    @Test func anOtherTagShowsItsNameUpToADotOrEquals() {
        let text = MagicDescriptionText.filled(
            "<Hello, Dragonborn>. <E = MC squared> <Alias.Name=X>", values: values
        )
        #expect(text == "Hello, Dragonborn. E  Alias")
    }

    @Test func anUnclosedTagStaysAsWritten() {
        #expect(MagicDescriptionText.filled("Heals <mag", values: values) == "Heals <mag")
    }

    @Test func numbersDropTrailingZeros() {
        #expect(MagicDescriptionText.number(10) == "10")
        #expect(MagicDescriptionText.number(0.5) == "0.5")
        #expect(MagicDescriptionText.number(1.25) == "1.25")
        #expect(MagicDescriptionText.number(2.05) == "2.05")
        #expect(MagicDescriptionText.number(-3) == "-3")
    }
}
