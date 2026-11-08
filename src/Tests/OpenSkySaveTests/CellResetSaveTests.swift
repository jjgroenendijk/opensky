// CRST chunk: the hour the player left each cell comes back after a save, so a cell
// still resets on time after a load.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct CellResetSaveTests {
    private let ledger = CellResetLedger(departures: [
        OpenSkySaveFixture.whiterun: 4_822_000.5,
        .interior(FormID(0x0001_6789)): 4_821_990
    ])

    private func snapshot(_ ledger: CellResetLedger) -> WorldStateSnapshot {
        OpenSkySaveFixture.snapshot(
            [OpenSkySaveFixture.entry(key: .player, cell: nil, components: [ledger.erased])],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
    }

    @Test func departuresSurviveAnEncodeAndDecode() throws {
        let original = snapshot(ledger)
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("CRST".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.component(CellResetLedger.self, for: .player) == ledger)
    }

    @Test func theSameDeparturesWriteTheSameBytes() {
        let reordered = CellResetLedger(departures: Dictionary(
            uniqueKeysWithValues: ledger.departures.reversed()
        ))
        #expect(
            OpenSkySaveFixture.encode(snapshot(ledger))
                == OpenSkySaveFixture.encode(snapshot(reordered))
        )
    }

    @Test func noDepartureWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        #expect(data.range(of: Data("CRST".utf8)) == nil)
    }

    @Test func aCountLargerThanThePayloadThrows() {
        var writer = BinaryWriter()
        writer.writeUInt32(1000)
        #expect(throws: (any Error).self) {
            try OpenSkySaveCellResetDecoder.decode(writer.data)
        }
    }
}
