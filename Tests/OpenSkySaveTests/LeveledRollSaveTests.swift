// LVRL chunk: a frozen leveled-roll level comes back, and a session that froze none
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
struct LeveledRollSaveTests {
    private let bandit = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_C0DE)

    @Test func aFrozenLevelSurvivesAnEncodeAndDecode() throws {
        let original = OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: bandit,
                    cell: .exterior(CellCoordinate(x: 5, y: -24)),
                    components: [LeveledRollState(playerLevel: 12).erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("LVRL".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        #expect(file.snapshot[bandit]?.component(LeveledRollState.self)?.playerLevel == 12)
    }

    @Test func noFrozenLevelWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        #expect(data.range(of: Data("LVRL".utf8)) == nil)
    }
}
