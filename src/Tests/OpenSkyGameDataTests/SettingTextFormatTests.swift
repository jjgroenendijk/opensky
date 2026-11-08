// Filling the places of a string setting, in order, without `String(format:)`.

@testable import OpenSkyGameData
import Testing

struct SettingTextFormatTests {
    @Test func placesFillInOrderAndMissingOnesStay() {
        #expect(SettingTextFormat.fill("%s Increased to %i", ["Smithing", "16"])
            == "Smithing Increased to 16")
        #expect(SettingTextFormat.fill("%d%% of %s", ["5"]) == "5% of %s")
        #expect(SettingTextFormat.fill("100%", []) == "100%")
    }
}
