// RLOC chunk: a reference moved into another cell comes back in that cell, and a
// session that moved nothing writes no chunk.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct RelocationSaveTests {
    private let prisoner = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_B131)
    private let cart = ReferenceRelocation(location: .exterior(CellCoordinate(x: 5, y: -24)))

    @Test func aMovedReferenceSurvivesAnEncodeAndDecode() throws {
        let original = OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: prisoner,
                    cell: .exterior(CellCoordinate(x: 5, y: -24)),
                    components: [cart.erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("RLOC".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        #expect(file.snapshot[prisoner]?.component(ReferenceRelocation.self) == cart)
    }

    @Test func noMoveWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        #expect(data.range(of: Data("RLOC".utf8)) == nil)
    }
}
