// A save row's title and detail in the game's save description words.

import OpenSkyGameData
import Testing

struct SaveTextsTests {
    @Test func autosaveAndQuicksaveSlotsUseTheGameWords() {
        var texts = SaveTexts.vanilla
        texts.autosaveAbbrev = "Auto"
        texts.quicksaveAbbrev = "Quick"
        #expect(texts.slotLabel("Autosave2") == "Auto 2")
        #expect(texts.slotLabel("Quicksave") == "Quick")
        #expect(texts.slotLabel("Save 4") == "Save 4")
        #expect(texts.title(slot: "Save 4", characterName: "") == "Save 4 - Prisoner")
    }

    @Test func theDetailNamesLevelPlaceAndPlayTime() {
        var texts = SaveTexts.vanilla
        texts.levelAbbrev = "Lvl"
        #expect(
            texts.detail(level: 12, location: "Whiterun", playTime: "1h 2m")
                == "Lvl 12: Whiterun, Play Time: 1h 2m"
        )
    }
}
