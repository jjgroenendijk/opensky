// The parts the menu adapters hand their reads to fall back when no records have loaded.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkySessionTesting
import Testing

@MainActor
struct MenuAdapterPartsTests {
    private let host = MenuHost()

    @Test func withoutRecordsTheRaceMenuIsEmpty() {
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<GenderText>.vanilla
        let races = MenuWorldAdapter(game: host, now: { Date() }).skillsRace
        #expect(races.playableRaces.isEmpty)
        #expect(races.raceMenuLabels == RaceMenuLabels(texts: [:], genders: .vanilla))
        #expect(races.raceMenuOptions(race: FormID(0x13746), isFemale: false) == .empty)
        #expect(races.racePresets(race: FormID(0x13746), isFemale: true).isEmpty)
        #expect(races.identityRecords == nil)
        #expect(races.recordIdentity == nil)
    }

    @Test func aPluginTextWithoutStringsHasNoText() {
        let map = MapWorldAdapter(game: host)
        let setting = ResolvedGameText(text: .tableID(7), sourcePlugin: "base.esm")
        #expect(map.text(setting) == nil)
        #expect(map.playerSetMarker == nil)
        let tamriel = ResolvedFormID(plugin: "base.esm", objectID: 0x3C)
        #expect(map.mapMarkerSites(in: tamriel).isEmpty)
    }
}
