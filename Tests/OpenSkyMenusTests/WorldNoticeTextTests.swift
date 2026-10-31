// The HUD shapes of world notices: big notices with their lines, and the map line.

import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyScriptingInterface
import Testing

struct WorldNoticeTextTests {
    private let texts = GameSettingTexts<WorldNoticeText>.vanilla

    @Test func aLocationShowsItsNameOverTheStatus() {
        #expect(WorldNoticeShape(.locationCleared(name: "Bleak Falls Barrow"), texts: texts)
            == .big(HUDBigNotice(title: "Bleak Falls Barrow", status: "Cleared")))
    }

    @Test func dragonSoulsCountInTheStatus() {
        #expect(WorldNoticeShape(.dragonSoulAbsorbed(souls: 1), texts: texts)
            == .big(HUDBigNotice(title: "Dragon Soul Absorbed", status: "1 Dragon Soul")))
        #expect(WorldNoticeShape(.dragonSoulAbsorbed(souls: 3), texts: texts)
            == .big(HUDBigNotice(title: "Dragon Soul Absorbed", status: "3 Dragon Souls")))
    }

    @Test func aWordUsesTheShoutLayoutAndAMarkerALine() {
        #expect(WorldNoticeShape(.wordLearned(word: "Fus"), texts: texts)
            == .big(HUDBigNotice(kind: .shout, title: "Fus", status: "Word of Power Learned")))
        #expect(WorldNoticeShape(.mapMarkerAdded, texts: texts) == .line("Map updated."))
    }
}
