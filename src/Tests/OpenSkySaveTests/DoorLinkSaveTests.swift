// RDLK chunk: a random door's link comes back, and a session with no link writes
// no chunk.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct DoorLinkSaveTests {
    private let cellarDoor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_2345)
    private let caveDoor = ReferenceKey.plugin(name: "dawnguard.esm", objectID: 0x0000_0ABC)

    @Test func bothSidesOfALinkSurviveAnEncodeAndDecode() throws {
        let original = OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: cellarDoor,
                    cell: .exterior(CellCoordinate(x: 5, y: -24)),
                    components: [ReferenceDoorLink(door: caveDoor).erased]
                ),
                OpenSkySaveFixture.entry(
                    key: caveDoor,
                    cell: .interior(FormID(0x0000_1D00)),
                    components: [ReferenceDoorLink(door: cellarDoor).erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("RDLK".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        #expect(file.snapshot[cellarDoor]?.component(ReferenceDoorLink.self)?.door == caveDoor)
    }

    @Test func noLinkWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        #expect(data.range(of: Data("RDLK".utf8)) == nil)
    }
}
