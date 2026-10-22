// The morph count settings, and their check against chargen TRI targets.

import OpenSkyEngineTesting
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct FaceMorphCountsTests {
    @Test func theCountsComeFromTheGame() throws {
        let store = try GameSettingFixture.store([
            "iEyeMorphCount": .integer(12), "iBrowMorphCount": .integer(5)
        ])
        let counts = FaceMorphCounts.resolve(store: store)
        #expect(counts.eye == 12 && counts.brow == 5)
        #expect(counts.nose == 31 && counts.lip == 31)
        #expect(counts.count(partIndex: 2) == 12)
        #expect(counts.count(partIndex: 1) == nil)
    }

    @Test func aTRIWithFewerTypesIsReported() {
        let names = (1 ... 30).map { "NoseType\($0)" } + (1 ... 28).map { "EyesType\($0)" }
            + (1 ... 30).map { "LipType\($0)" } + ["BrowUp"]
        #expect(FaceMorphCounts.vanilla.mismatches(targetNames: names)
            == ["iEyeMorphCount 38, chargen TRI holds 29"])
    }
}
