// The outlines of a worldspace's border regions, which hold the player inside.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import Testing

struct BorderOutlineTests {
    private static let worldspace: UInt32 = 0x3C

    @Test func onlyABorderRegionOfTheWorldspaceGivesAnOutline() throws {
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup(
                "REGN",
                contents: Self.region(0x100, flags: 0x40, worldspace: Self.worldspace)
                    + Self.region(0x101, flags: 0, worldspace: Self.worldspace)
                    + Self.region(0x102, flags: 0x40, worldspace: 0x99)
            )
        let store = try WeatherStore(file: ESMFile(data: plugin))
        let outlines = store.borderOutlines(worldspace: Self.worldspace)
        #expect(outlines == [[SIMD2(0, 0), SIMD2(100, 0), SIMD2(0, 100)]])
        #expect(store.borderOutlines(worldspace: 0x77).isEmpty)
    }

    @Test func theBorderNoticeHasOpenSkysWordsWithoutTheSetting() {
        #expect(GameSettingTexts<WorldRefusalText>
            .vanilla[.leavingBorderRegion] == "You cannot go that way.")
    }

    @Test func theMagicMenuTabsRunFromTheSchoolsToShoutsAndPowers() {
        #expect(MagicTexts.vanilla.menuCategoryOrder == [
            "ALTERATION", "ILLUSION", "DESTRUCTION", "CONJURATION", "RESTORATION", "SHOUTS",
            "POWERS"
        ])
    }

    private static func region(_ formID: UInt32, flags: UInt32, worldspace: UInt32) -> Data {
        var wnam = Data()
        wnam.appendUInt32(worldspace)
        var rpli = Data()
        rpli.appendUInt32(0)
        var rpld = Data()
        for (x, y) in [(0, 0), (100, 0), (0, 100)] as [(Float, Float)] {
            rpld.appendFloat32(x)
            rpld.appendFloat32(y)
        }
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Region\(formID)"))
            + ESMFixture.field("WNAM", wnam)
            + ESMFixture.field("RPLI", rpli)
            + ESMFixture.field("RPLD", rpld)
        return ESMFixture.record("REGN", formID: formID, flags: flags, data: fields)
    }
}
