// A key named by an agent: a scan code in hex or decimal, or the name the page shows.

import OpenSkyGameData
import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct PlayerSettingsKeyLookupTests {
    private let settings = PlayerSettingsCoordinator(store: PlayerSettingsStore(persistence: nil))

    @Test func scanCodesReadAsHexOrDecimal() {
        #expect(settings.scanCode(named: "0x39") == 0x39)
        #expect(settings.scanCode(named: "57") == 0x39)
        #expect(settings.scanCode(named: "0x00") == nil, "no key has code 0")
    }

    @Test func namesMatchTheShownNameIgnoringCase() {
        #expect(settings.scanCode(named: "space") == 0x39)
        #expect(settings.scanCode(named: " E ") == 0x12)
        #expect(settings.scanCode(named: "NoSuchKey") == nil)
    }

    @Test func aKeyFiresItsBoundAction() {
        #expect(settings.action(forScanCode: 0x11, inMenu: false) == .forward)
        #expect(settings.action(forScanCode: 0xFF, inMenu: false) == nil)
    }
}
