// RMOT chunk: a motion type a script set comes back, and a session that set none
// writes no chunk.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct MotionTypeSaveTests {
    private let boulder = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_B131)
    private let rock = ReferenceMotionType.dynamic

    @Test func aMotionTypeSurvivesAnEncodeAndDecode() throws {
        let original = OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: boulder,
                    cell: .exterior(CellCoordinate(x: 5, y: -24)),
                    components: [rock.erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("RMOT".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        #expect(file.snapshot[boulder]?.component(ReferenceMotionType.self) == rock)
    }

    @Test func noMotionTypeWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        #expect(data.range(of: Data("RMOT".utf8)) == nil)
    }
}
